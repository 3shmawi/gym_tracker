// Two small SVG charts for D5, no chart library (nothing to pin or audit).
// Single series each, so no legend box: the panel title names it. Colour is
// the --chart token, checked with the dataviz validator against both
// surfaces (light #15803D, dark #16A34A: lightness band, chroma, ≥ 3:1).
// Every mark has a <title> (the hover tooltip); the svg has a text summary
// as its name, and the page shows the same numbers as a table. Time runs
// left to right in both languages, like the app's charts.

export interface Bar {
  readonly key: string;
  readonly value: number;
  readonly tick: string | null;
  readonly tip: string;
}

const W = 600;
const H = 200;
const PAD = { top: 16, right: 12, bottom: 28, left: 28 };

export function BarChart({ bars, threshold, thresholdLabel, label }: { readonly bars: readonly Bar[]; readonly threshold: number; readonly thresholdLabel: string; readonly label: string }) {
  const max = Math.max(threshold + 1, ...bars.map((b) => b.value));
  const innerW = W - PAD.left - PAD.right;
  const innerH = H - PAD.top - PAD.bottom;
  const slot = innerW / Math.max(1, bars.length);
  const barW = Math.max(4, slot - 6);
  const y = (v: number) => PAD.top + innerH - (v / max) * innerH;
  const ticks = [0, Math.ceil(max / 2), max];
  return (
    <div class="chart" dir="ltr">
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={label} preserveAspectRatio="xMidYMid meet">
        {ticks.map((v) => (
          <g key={v} aria-hidden="true">
            <line class="grid" x1={PAD.left} x2={W - PAD.right} y1={y(v)} y2={y(v)} />
            <text class="axis" x={PAD.left - 6} y={y(v) + 4} text-anchor="end">{v}</text>
          </g>
        ))}
        <g aria-hidden="true">
          <line class="threshold" x1={PAD.left} x2={W - PAD.right} y1={y(threshold)} y2={y(threshold)} />
          <text class="axis" x={W - PAD.right} y={y(threshold) - 4} text-anchor="end">{thresholdLabel}</text>
        </g>
        {bars.map((b, i) => {
          const x = PAD.left + i * slot + (slot - barW) / 2;
          const h = Math.max(0, y(0) - y(b.value));
          return (
            <g key={b.key}>
              <title>{b.tip}</title>
              {/* a hit area taller than the mark, so the tooltip is easy to reach */}
              <rect class="hit" x={PAD.left + i * slot} y={PAD.top} width={slot} height={innerH} />
              {b.value > 0 ? <rect class="mark" x={x} y={y(b.value)} width={barW} height={h} rx={Math.min(4, barW / 2)} /> : <line class="zero" x1={x} x2={x + barW} y1={y(0)} y2={y(0)} />}
              {b.tick ? <text class="axis" x={x + barW / 2} y={H - 8} text-anchor="middle" aria-hidden="true">{b.tick}</text> : null}
            </g>
          );
        })}
      </svg>
    </div>
  );
}

export interface Point {
  readonly key: string;
  readonly value: number;
  readonly record: boolean;
  readonly tick: string | null;
  readonly tip: string;
}

export function LineChart({ points, label, recordLabel }: { readonly points: readonly Point[]; readonly label: string; readonly recordLabel: string }) {
  const values = points.map((p) => p.value);
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const span = hi - lo || Math.max(1, hi * 0.1);
  const min = Math.max(0, lo - span * 0.15);
  const max = hi + span * 0.15;
  const innerW = W - PAD.left - PAD.right;
  const innerH = H - PAD.top - PAD.bottom;
  const x = (i: number) => PAD.left + (points.length === 1 ? innerW / 2 : (i / (points.length - 1)) * innerW);
  const y = (v: number) => PAD.top + innerH - ((v - min) / (max - min)) * innerH;
  const path = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(p.value).toFixed(1)}`).join(' ');
  const fmt = (v: number) => (Math.round(v * 10) / 10).toString();
  return (
    <div class="chart" dir="ltr">
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={label} preserveAspectRatio="xMidYMid meet">
        {[min, (min + max) / 2, max].map((v) => (
          <g key={v} aria-hidden="true">
            <line class="grid" x1={PAD.left} x2={W - PAD.right} y1={y(v)} y2={y(v)} />
            <text class="axis" x={PAD.left - 6} y={y(v) + 4} text-anchor="end">{fmt(v)}</text>
          </g>
        ))}
        <path class="line" d={path} aria-hidden="true" />
        {points.map((p, i) => (
          <g key={p.key}>
            <title>{p.record ? `${p.tip} · ${recordLabel}` : p.tip}</title>
            <circle class="hit" cx={x(i)} cy={y(p.value)} r={14} />
            {p.record ? <rect class="record" x={x(i) - 6} y={y(p.value) - 6} width={12} height={12} transform={`rotate(45 ${x(i)} ${y(p.value)})`} /> : <circle class="dot" cx={x(i)} cy={y(p.value)} r={4} />}
            {p.tick ? <text class="axis" x={x(i)} y={H - 8} text-anchor="middle" aria-hidden="true">{p.tick}</text> : null}
          </g>
        ))}
      </svg>
    </div>
  );
}
