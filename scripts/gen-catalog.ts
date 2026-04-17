#!/usr/bin/env bun
/**
 * Generate Swift DeviceDescriptor files from openrazer upstream.
 *
 * Zero hardcoded per-device quirks — every value is extracted from openrazer:
 *   • PID + display name + METHODS → openrazer Python daemon hardware/*.py
 *   • transaction_id per PID       → switch-cases in driver/*.c
 *   • isWireless per PID           → `_WIRED`/`_WIRELESS`/`_RECEIVER`/`_DONGLE`
 *                                    suffixes on the USB_DEVICE_ID_* constant
 *   • hyper polling rate support   → PIDs routed to `set_polling_rate2` in
 *                                    `razer_attr_write_poll_rate` case blocks
 *
 * Regenerate: bun run scripts/gen-catalog.ts
 */

import { mkdir, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const REPO = 'openrazer/openrazer'
const BRANCH = 'master'
const BASE = `https://raw.githubusercontent.com/${REPO}/${BRANCH}`

type Category = 'mouse' | 'keyboard' | 'headset' | 'mousepad' | 'accessory'

const PY_HARDWARE: { category: Category; path: string }[] = [
    { category: 'mouse', path: 'daemon/openrazer_daemon/hardware/mouse.py' },
    { category: 'keyboard', path: 'daemon/openrazer_daemon/hardware/keyboards.py' },
    { category: 'headset', path: 'daemon/openrazer_daemon/hardware/headsets.py' },
    { category: 'mousepad', path: 'daemon/openrazer_daemon/hardware/mouse_mat.py' },
    { category: 'accessory', path: 'daemon/openrazer_daemon/hardware/accessory.py' },
]

const C_DRIVERS: string[] = [
    'driver/razermouse_driver.h',
    'driver/razerkbd_driver.h',
    'driver/razeraccessory_driver.h',
    'driver/razerkraken_driver.h',
    'driver/razermouse_driver.c',
    'driver/razerkbd_driver.c',
    'driver/razeraccessory_driver.c',
    'driver/razerkraken_driver.c',
]

type ParsedClass = {
    name: string
    parents: string[]
    pid?: number
    dpiMax?: number
    methodsLocal: string[]
    methodsFromParent: boolean
}

type ResolvedDevice = ParsedClass & {
    methods: string[]
    category: Category
}

const METHOD_TO_CAP: Record<string, string> = {
    // DPI / polling
    set_dpi_xy: '.dpi',
    get_dpi_xy: '.dpi',
    set_dpi_xy_byte: '.dpi',
    set_dpi_stages: '.dpiStages',
    get_dpi_stages: '.dpiStages',
    set_poll_rate: '.pollingRate',
    get_poll_rate: '.pollingRate',
    set_poll_rate_ex: '.pollingRateHyper',
    get_poll_rate_ex: '.pollingRateHyper',

    // Battery / power
    get_battery: '.battery',
    is_charging: '.charging',
    set_idle_time: '.idleTimer',
    get_idle_time: '.idleTimer',
    set_low_battery_threshold: '.lowBatteryThreshold',
    get_low_battery_threshold: '.lowBatteryThreshold',

    // Brightness (classic + per-zone)
    set_brightness: '.brightness',
    get_brightness: '.brightness',
    set_logo_brightness: '.brightness',
    set_scroll_brightness: '.brightness',
    set_left_brightness: '.brightness',
    set_right_brightness: '.brightness',
    set_backlight_brightness: '.brightness',

    // RGB effects — classic (class 0x03)
    set_static_effect: '.rgbStatic',
    set_logo_static: '.rgbStatic',
    set_scroll_static: '.rgbStatic',
    set_breath_single_effect: '.rgbBreathe',
    set_breath_dual_effect: '.rgbBreathe',
    set_breath_random_effect: '.rgbBreathe',
    set_logo_breath_single: '.rgbBreathe',
    set_scroll_breath_single: '.rgbBreathe',
    set_spectrum_effect: '.rgbSpectrum',
    set_logo_spectrum: '.rgbSpectrum',
    set_scroll_spectrum: '.rgbSpectrum',
    set_wave_effect: '.rgbWave',
    set_logo_wave: '.rgbWave',
    set_wave_effect_extended: '.rgbWave',
    set_reactive_effect: '.rgbReactive',
    set_logo_reactive: '.rgbReactive',
    set_starlight_single_effect: '.rgbStarlight',
    set_starlight_dual_effect: '.rgbStarlight',
    set_starlight_random_effect: '.rgbStarlight',

    // Custom per-key frame (keyboard matrix)
    set_key_row: '.customFrame',
    set_custom_effect: '.customFrame',

    // Extended effect path (class 0x0F) — presence of any "logo_*" effect
    // typically indicates extended routing on modern devices.
    set_logo_none: '.extendedEffects',
}

const COMPOUND_NAMES = [
    'DeathAdder', 'DeathStalker', 'BlackWidow', 'BlackShark',
    'HyperPolling', 'HyperSpeed', 'HyperFlux', 'BladeStealth',
]

const fetchText = async (path: string): Promise<string> => {
    const res = await fetch(`${BASE}/${path}`)
    if (!res.ok) throw new Error(`${res.status} ${path}`)
    return res.text()
}

// =====================================================================
// C driver parsing
// =====================================================================

type DriverMaps = {
    /** USB_DEVICE_ID_RAZER_* → PID */
    constantToPid: Map<string, number>
    /** PID → USB_DEVICE_ID_RAZER_* */
    pidToConstant: Map<number, string>
    /** PID → most common transaction_id observed across switch-cases */
    pidToTransactionID: Map<number, number>
    /** PIDs that get routed to `set_polling_rate2` (hyperpolling command) */
    hyperPollingPids: Set<number>
}

const parseHeaderDefines = (source: string, out: Map<string, number>): void => {
    for (const m of source.matchAll(/^#define\s+(USB_DEVICE_ID_RAZER_\w+)\s+0x([0-9A-Fa-f]+)/gm)) {
        out.set(m[1]!, parseInt(m[2]!, 16))
    }
}

/**
 * Walk a .c source scanning for `case USB_DEVICE_ID_RAZER_X:` groups and the
 * `request.transaction_id.id = 0xVV;` assignment that follows them. Returns
 * a list of (constants, txid) observations.
 */
const extractTransactionObservations = (source: string): { constants: string[]; txid: number }[] => {
    const lines = source.split('\n')
    const observations: { constants: string[]; txid: number }[] = []
    let group: string[] = []

    for (const line of lines) {
        const caseMatch = /^\s*case\s+(USB_DEVICE_ID_RAZER_\w+)\s*:/.exec(line)
        const txidMatch = /transaction_id\.id\s*=\s*0x([0-9A-Fa-f]+)/.exec(line)

        if (caseMatch) {
            group.push(caseMatch[1]!)
        } else if (txidMatch && group.length > 0) {
            observations.push({ constants: [...group], txid: parseInt(txidMatch[1]!, 16) })
            group = []
        } else if (/^\s*break\s*;/.test(line) || /^\s*return\s/.test(line)) {
            group = []
        }
    }
    return observations
}

/**
 * Walk a .c source for case-groups that flow into a `set_polling_rate2(` call,
 * which indicates hyperpolling support.
 */
const extractHyperPollingConstants = (source: string): Set<string> => {
    const hyper = new Set<string>()
    const lines = source.split('\n')
    let group: string[] = []

    for (const line of lines) {
        const caseMatch = /^\s*case\s+(USB_DEVICE_ID_RAZER_\w+)\s*:/.exec(line)
        if (caseMatch) {
            group.push(caseMatch[1]!)
            continue
        }
        if (/razer_chroma_misc_set_polling_rate2\s*\(/.test(line)) {
            for (const c of group) hyper.add(c)
            // don't reset yet — group may flow into other calls too
        }
        if (/^\s*break\s*;/.test(line) || /^\s*return\s/.test(line)) {
            group = []
        }
    }
    return hyper
}

const loadDriverMaps = async (): Promise<DriverMaps> => {
    const maps: DriverMaps = {
        constantToPid: new Map(),
        pidToConstant: new Map(),
        pidToTransactionID: new Map(),
        hyperPollingPids: new Set(),
    }
    const txidByConstant: Map<string, number[]> = new Map()
    const hyperConstants = new Set<string>()

    for (const path of C_DRIVERS) {
        const source = await fetchText(path)
        if (path.endsWith('.h')) {
            parseHeaderDefines(source, maps.constantToPid)
        } else {
            for (const obs of extractTransactionObservations(source)) {
                for (const c of obs.constants) {
                    if (!txidByConstant.has(c)) txidByConstant.set(c, [])
                    txidByConstant.get(c)!.push(obs.txid)
                }
            }
            for (const c of extractHyperPollingConstants(source)) hyperConstants.add(c)
        }
    }

    for (const [c, pid] of maps.constantToPid) {
        if (!maps.pidToConstant.has(pid)) maps.pidToConstant.set(pid, c)
    }

    for (const [c, observations] of txidByConstant) {
        const pid = maps.constantToPid.get(c)
        if (pid === undefined) continue
        const counts: Record<number, number> = {}
        for (const t of observations) counts[t] = (counts[t] ?? 0) + 1
        const [[best]] = Object.entries(counts).sort((a, b) => b[1] - a[1]) as [string, number][][]
        maps.pidToTransactionID.set(pid, parseInt(best!, 10))
    }

    for (const c of hyperConstants) {
        const pid = maps.constantToPid.get(c)
        if (pid !== undefined) maps.hyperPollingPids.add(pid)
    }

    return maps
}

// =====================================================================
// Python daemon parsing
// =====================================================================

const splitClasses = (source: string): { header: string; body: string }[] => {
    const lines = source.split('\n')
    const chunks: { header: string; body: string }[] = []
    let currentHeader: string | null = null
    let currentBody: string[] = []

    for (const line of lines) {
        if (/^class\s+\w+/.test(line)) {
            if (currentHeader) chunks.push({ header: currentHeader, body: currentBody.join('\n') })
            currentHeader = line
            currentBody = []
        } else if (currentHeader) {
            currentBody.push(line)
        }
    }
    if (currentHeader) chunks.push({ header: currentHeader, body: currentBody.join('\n') })
    return chunks
}

const parseClass = (header: string, body: string): ParsedClass | null => {
    const headerMatch = /^class\s+(\w+)\s*(?:\(([^)]*)\))?/.exec(header)
    if (!headerMatch) return null
    const name = headerMatch[1]!
    const parentsRaw = headerMatch[2] ?? ''
    const parents = parentsRaw
        .split(',')
        .map((s) => s.trim())
        .filter((s) => s.length > 0)
        .map((s) => s.replace(/^__/, ''))
        .filter((s) => !s.startsWith('object'))

    const pidMatch = /^\s*USB_PID\s*=\s*0x([0-9A-Fa-f]+)/m.exec(body)
    const dpiMatch = /^\s*DPI_MAX\s*=\s*(\d+)/m.exec(body)

    const methodsBlockMatch =
        /^\s*METHODS\s*=\s*([\s\S]*?)(?=^\s*[A-Z_]{3,}\s*=|^\s*DEVICE_IMAGE\s*=|^class\s|\Z)/m.exec(body)
    const methodsLocal: string[] = []
    let methodsFromParent = false
    if (methodsBlockMatch) {
        const raw = methodsBlockMatch[1]!
        methodsFromParent = /\.METHODS\s*\+/.test(raw) || /\+\s*[A-Za-z_][\w.]*\.METHODS/.test(raw)
        for (const [, a, b] of raw.matchAll(/'([^']+)'|"([^"]+)"/g)) {
            const v = a ?? b
            if (v && /^[a-z_][a-z0-9_]*$/.test(v)) methodsLocal.push(v)
        }
    }

    return {
        name,
        parents,
        pid: pidMatch ? parseInt(pidMatch[1]!, 16) : undefined,
        dpiMax: dpiMatch ? parseInt(dpiMatch[1]!, 10) : undefined,
        methodsLocal,
        methodsFromParent,
    }
}

const resolveMethods = (
    cls: ParsedClass,
    byName: Map<string, ParsedClass>,
    visiting = new Set<string>(),
): string[] => {
    if (visiting.has(cls.name)) return cls.methodsLocal
    visiting.add(cls.name)

    const combined = new Set<string>()
    const inheritAll = cls.methodsLocal.length === 0 && !cls.methodsFromParent

    if (cls.methodsFromParent || inheritAll) {
        for (const parent of cls.parents) {
            const p = byName.get(parent)
            if (p) for (const m of resolveMethods(p, byName, visiting)) combined.add(m)
        }
    }
    for (const m of cls.methodsLocal) combined.add(m)
    return Array.from(combined)
}

const resolveDpiMax = (
    cls: ParsedClass,
    byName: Map<string, ParsedClass>,
    visiting = new Set<string>(),
): number | undefined => {
    if (cls.dpiMax !== undefined) return cls.dpiMax
    if (visiting.has(cls.name)) return undefined
    visiting.add(cls.name)
    for (const parent of cls.parents) {
        const p = byName.get(parent)
        if (p) {
            const v = resolveDpiMax(p, byName, visiting)
            if (v !== undefined) return v
        }
    }
    return undefined
}

const capabilitiesOf = (methods: string[]): string[] => {
    const caps = new Set<string>()
    for (const m of methods) {
        const cap = METHOD_TO_CAP[m]
        if (cap) caps.add(cap)
    }
    return Array.from(caps).sort()
}

// =====================================================================
// Display helpers
// =====================================================================

const displayName = (clsName: string): string => {
    let s = clsName.replace(/_Alternate/g, ' (Alt)').replace(/_/g, ' ')
    s = s.replace(/^Razer/, 'Razer ')
    s = s.replace(/([a-z])([A-Z])/g, '$1 $2')
    s = s.replace(/([A-Z])([A-Z][a-z])/g, '$1 $2')
    s = s.replace(/(\d)([A-Z])/g, '$1 $2')
    s = s.replace(/([A-Za-z])(\d{4,})/g, '$1 $2')

    for (const compound of COMPOUND_NAMES) {
        const split = compound.replace(/([a-z])([A-Z])/g, '$1 $2')
        if (split !== compound) s = s.split(split).join(compound)
    }
    s = s.replace(/(\d) K\b/g, '$1K')
    return s.replace(/\s+/g, ' ').trim()
}

const shortNameOf = (display: string): string =>
    display.startsWith('Razer ') ? display.slice('Razer '.length) : display

const swiftEscape = (s: string): string => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')

const isWirelessFromConstant = (constant: string | undefined): boolean => {
    if (!constant) return false
    return /_WIRELESS|_RECEIVER|_DONGLE/.test(constant) && !/_WIRED/.test(constant)
}

// =====================================================================
// Swift emission
// =====================================================================

const emitSwift = (category: Category, devices: ResolvedDevice[], maps: DriverMaps): string => {
    const typeName = `Generated${category[0]!.toUpperCase() + category.slice(1)}Catalog`
    const lines: string[] = [
        '// AUTO-GENERATED by scripts/gen-catalog.ts — do not edit by hand.',
        '// Regenerate: bun run scripts/gen-catalog.ts',
        `// Source: github.com/${REPO} @ ${BRANCH}`,
        '',
        'import Foundation',
        '',
        `enum ${typeName} {`,
        '    static let descriptors: [DeviceDescriptor] = [',
    ]

    const seen = new Set<number>()
    for (const d of devices.sort((a, b) => a.name.localeCompare(b.name))) {
        if (d.pid === undefined) continue
        if (seen.has(d.pid)) continue
        seen.add(d.pid)
        const caps = capabilitiesOf(d.methods)
        if (caps.length === 0) continue

        const constant = maps.pidToConstant.get(d.pid)
        const txid = maps.pidToTransactionID.get(d.pid) ?? 0xff
        const wireless = isWirelessFromConstant(constant)
        const hyper = maps.hyperPollingPids.has(d.pid)

        const display = displayName(d.name)
        const short = shortNameOf(display)
        const dpi =
            d.dpiMax ??
            (d.methods.includes('set_dpi_xy') ? 30000 : d.methods.includes('set_dpi_xy_byte') ? 8500 : 0)
        const hyperRates = hyper
            ? '[.hz125, .hz500, .hz1000, .hz2000, .hz4000, .hz8000]'
            : '[]'
        const effectiveCaps = hyper && !caps.includes('.pollingRateHyper')
            ? [...caps, '.pollingRateHyper'].sort()
            : caps

        lines.push(`        DeviceDescriptor(
            displayName: "${swiftEscape(display)}",
            shortName: "${swiftEscape(short)}",
            category: .${category},
            productIDs: [0x${d.pid.toString(16).toUpperCase().padStart(4, '0')}],
            capabilities: [${effectiveCaps.join(', ')}],
            maxDPI: ${dpi},
            hyperPollingRates: ${hyperRates},
            isWireless: ${wireless},
            transactionID: TransactionID(rawValue: 0x${txid.toString(16).padStart(2, '0')})
        ),`)
    }

    lines.push('    ]')
    lines.push('}')
    lines.push('')
    return lines.join('\n')
}

// =====================================================================
// Entry point
// =====================================================================

const run = async () => {
    console.log('==> Fetching openrazer C drivers (headers + switch-cases)')
    const maps = await loadDriverMaps()
    console.log(
        `    ${maps.constantToPid.size} PIDs, ${maps.pidToTransactionID.size} with extracted transaction_id, ${maps.hyperPollingPids.size} hyperpolling-capable`,
    )

    const outDir = resolve(import.meta.dir, '..', 'Sources/RazerKit/Catalog/Generated')
    await mkdir(outDir, { recursive: true })

    let totalEmitted = 0
    const txidHistogram: Record<string, number> = {}
    const unresolvedTxid: string[] = []

    for (const { category, path } of PY_HARDWARE) {
        process.stdout.write(`==> ${path}\n`)
        const source = await fetchText(path).catch((e) => {
            console.log(`    skip (${(e as Error).message})`)
            return ''
        })
        if (!source) continue

        const classes = splitClasses(source)
        const byName = new Map<string, ParsedClass>()
        for (const { header, body } of classes) {
            const parsed = parseClass(header, body)
            if (parsed) byName.set(parsed.name, parsed)
        }

        const resolved: ResolvedDevice[] = []
        for (const cls of byName.values()) {
            if (cls.pid === undefined) continue
            const methods = resolveMethods(cls, byName)
            const dpiMax = resolveDpiMax(cls, byName)
            resolved.push({ ...cls, methods, dpiMax, category })

            const txid = maps.pidToTransactionID.get(cls.pid)
            if (txid === undefined) unresolvedTxid.push(cls.name)
            else txidHistogram[txid.toString(16)] = (txidHistogram[txid.toString(16)] ?? 0) + 1
        }

        const swift = emitSwift(category, resolved, maps)
        const outPath = resolve(outDir, `${category[0]!.toUpperCase() + category.slice(1)}Catalog.swift`)
        await writeFile(outPath, swift, 'utf-8')
        const emitted = resolved.filter((d) => capabilitiesOf(d.methods).length > 0).length
        console.log(`    wrote ${outPath.replace(process.cwd() + '/', '')} (${emitted} devices)`)
        totalEmitted += emitted
    }

    console.log('')
    console.log(`Transaction ID distribution: ${JSON.stringify(txidHistogram)}`)
    if (unresolvedTxid.length > 0) {
        console.log(
            `No transaction_id observed in switch-cases for ${unresolvedTxid.length} devices (using 0xFF fallback):`,
        )
        for (const n of unresolvedTxid.slice(0, 10)) console.log(`    · ${n}`)
        if (unresolvedTxid.length > 10) console.log(`    · … and ${unresolvedTxid.length - 10} more`)
    }
    console.log(`\nDone. ${totalEmitted} descriptors emitted.`)
}

run().catch((e) => {
    console.error(e)
    process.exit(1)
})
