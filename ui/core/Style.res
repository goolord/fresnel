// The view's stylesheet. Every colour, font, radius and shadow comes from the theme's custom
// properties (Theme.res), so restyling is done there, not here; this file is the layout of each
// element. Sizes are design pixels: the stage is laid out at the design size and scaled to the
// window (Shell.res).

let designWidth = Config.designWidth
let designHeight = Config.designHeight
let headerHeight = 34.
let statusHeight = 22.
// the area pages lay their panels out in
let pageHeight = designHeight - headerHeight - statusHeight

let px = Web.px

// Every control (parameter, list, switch, grid button) is one cell tall: this height, in a
// grid row this much taller (Grid.rowHeight), so that neighbours never touch.
let controlHeight = 26.
let controlGap = 2.

// More CSS from widgets that keep their styles with them (a widget calls register at its top level,
// and the view puts it after css when it opens). Use the theme's properties here too.
let extras: array<string> = []
let register = css => extras->Array.push(css)


let css = `
:host, plugin-view {
    display: block;
    position: relative;
    /* important, because Cmajor sets the manifest's size on the view as an inline style, which
       would pin it at the design size and stop the stage scaling with the window */
    width: 100% !important;
    height: 100% !important;
    overflow: hidden;
    background: var(--ground);
    font-family: var(--font);
    font-stretch: var(--font-stretch);
    color: var(--ink);
    user-select: none;
    -webkit-user-select: none;
    cursor: default;
}

.pv-stage {
    position: absolute;
    left: 0;
    top: 0;
    width: ${px(designWidth)};
    height: ${px(designHeight)};
    transform-origin: 0 0;
}

.pv-page { position: absolute; left: 0; right: 0; top: ${px(headerHeight)}; bottom: ${px(statusHeight)}; display: none; }
.pv-page.on { display: block; }

.blk {
    position: absolute;
    box-sizing: border-box;
    background: var(--panel);
    border: 1px solid var(--edge);
    border-radius: var(--radius);
    padding: 4px 6px 5px 6px;
}
.blk > .ttl {
    position: absolute;
    left: 7px;
    top: 3px;
    font-weight: var(--title-weight);
    font-size: 14px;
    letter-spacing: 0.01em;
    text-transform: var(--title-case);
    color: var(--ink);
    pointer-events: none;
}

/* panel tabs: the active one is filled with the signal ink */
.ptabs { position: absolute; left: 3px; top: 2px; display: flex; gap: 1px; z-index: 1; }
.ptab {
    display: flex; align-items: center; padding: 0 7px; height: 18px; box-sizing: border-box; border-radius: var(--radius-sm);
    font-size: 13px; font-weight: var(--title-weight); color: var(--ink-faint); cursor: pointer; white-space: nowrap;
    text-transform: var(--title-case);
}
.ptab { background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge); }
.ptab:hover { color: var(--ink); background: var(--panel-hi); }
.ptab.on { color: var(--on-signal); background: var(--signal); }
.pbody { position: absolute; inset: 0; display: none; }
.pbody.on { display: block; }
.pbody.cover { background: var(--panel); z-index: 1; border-radius: inherit; }
.blk:has(> .pbody.cover.on) > .ptabs { z-index: 2; }
.blk > .hdr, .pbody > .hdr { position: absolute; right: 6px; top: 1px; width: 40px; height: 18px; }

/* a parameter row: label left, value right, position track underneath, on a tile */
.p {
    position: absolute;
    box-sizing: border-box;
    height: ${px(controlHeight)};
    padding: 1px 3px 0 3px;
    border-radius: var(--radius-sm);
    cursor: ns-resize;
    background: var(--tile);
    box-shadow: inset 0 0 0 1px var(--tile-edge);
}
.p:hover, .p.drag { background: var(--panel-hi); box-shadow: inset 0 0 0 1px var(--edge); }
.p .l {
    position: absolute; left: 3px; top: 1px;
    font-size: 11px; color: var(--ink-soft); white-space: nowrap; text-transform: var(--label-case);
}
.p .v {
    position: absolute; right: 3px; top: 10px;
    font-size: 12.5px; font-variant-numeric: tabular-nums; white-space: nowrap;
}
.p .t {
    position: absolute; left: 3px; right: 3px; bottom: 1px; height: 2px;
    background: rgba(var(--ink-rgb), 0.14);
}
.p .t i {
    position: absolute; top: 0; bottom: 0; background: var(--signal);
}
/* the range modulation sweeps */
.p .t em { position: absolute; top: -1px; bottom: -1px; background: var(--mod); opacity: 0.6; display: none; }
.p.dim .v, .p.dim .l { opacity: 0.45; }

/* choice: same footprint, click opens the menu, right click steps; a value with an icon shows both */
.p .v.withicon { display: flex; align-items: center; gap: 2px; top: 9px; max-width: calc(100% - 6px); }
.p .v .ic { height: 12px; color: var(--signal); }
.p.ch .v.withicon::after { margin-left: 1px; flex: none; }
.p.ch { cursor: pointer; }
.p.ch .v::after { content: ""; display: inline-block; width: 0; height: 0; margin-left: 4px;
    border-left: 3px solid transparent; border-right: 3px solid transparent; border-top: 4px solid var(--ink-faint);
    vertical-align: 2px; }

/* toggle: a switch on the same tile, and in the same footprint, as a parameter */
.tg {
    position: absolute; box-sizing: border-box; height: ${px(controlHeight)}; cursor: pointer;
    font-size: 12px; color: var(--ink-soft); display: flex; align-items: center; gap: 5px;
    white-space: nowrap; overflow: hidden; padding: 0 5px; border-radius: var(--radius-sm);
    background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge);
}
.tg:hover { background: var(--panel-hi); box-shadow: inset 0 0 0 1px var(--edge); }
.tg b { flex: none; width: 11px; height: 11px; border: 1.5px solid var(--ink); box-sizing: border-box; border-radius: 1px; background: transparent; }
.tg.on b { background: var(--signal); border-color: var(--signal); box-shadow: inset 0 0 0 1.5px var(--paper); }
.tg.on { color: var(--ink); }
.tg span { overflow: hidden; text-overflow: ellipsis; text-transform: var(--label-case); }
/* in a title row, a switch is as tall as the tabs */
.hdr .tg { height: 18px; font-size: 11.5px; }
.hdr .tg b { width: 9px; height: 9px; border-width: 1px; box-shadow: none; }

.btn {
    position: absolute; height: 20px; box-sizing: border-box; padding: 0 8px;
    display: inline-flex; align-items: center; justify-content: center; gap: 5px; white-space: nowrap;
    border: 1px solid var(--edge); border-radius: var(--radius-sm); background: var(--panel-hi);
    font: inherit; font-size: 12px; line-height: 1; color: var(--ink); cursor: pointer;
}
.btn:hover { background: var(--paper); }
.btn:active { background: var(--signal); color: var(--on-signal); }
.btn.on { background: var(--signal); color: var(--on-signal); border-color: var(--signal); }
/* a button in a grid cell */
.btn.gc { height: ${px(controlHeight)}; padding: 0 4px; }

.plot { position: absolute; display: block; }
.plot path.curve { fill: none; stroke: var(--signal); stroke-width: 1.4; }
.plot path.fill { fill: var(--signal-soft); stroke: none; }
.plot path.axis, .plot line.axis { stroke: rgba(var(--ink-rgb), 0.28); stroke-width: 1; fill: none; }
.plot.off { opacity: 0.4; }
.plot path.curve.depth { stroke: var(--mod); stroke-width: 1.2; stroke-dasharray: 4 3; }
.plot text.tick.depth { fill: var(--mod); }
.plot rect.bg { fill: rgba(var(--paper-rgb), 0.35); stroke: var(--edge); stroke-width: 1; }
.plot path.curve.faint { stroke-width: 1; stroke-dasharray: 3 2; opacity: 0.7; }
.plot path.curve.dim { stroke-width: 1; opacity: 0.45; }
.plot path.curve.fill { fill: var(--signal-soft); stroke-width: 1; }
.plot line.grid { stroke: rgba(var(--ink-rgb), 0.1); stroke-width: 1; }
.plot line.mark { stroke: var(--ink-faint); stroke-width: 1.2; stroke-dasharray: 3 3; }
.plot line.curve { stroke: var(--signal); stroke-width: 2; }
.plot line.curve.alt { stroke: var(--mod); }
.plot circle.dot { fill: var(--signal); }
.plot text.readout { font-size: 11px; font-weight: var(--title-weight); fill: var(--signal); }
.plot line.axis.faint { stroke: rgba(var(--ink-rgb), 0.12); }
.plot text.tick { font-size: 10px; fill: var(--ink-faint); }

/* graphical editors (envelopes): drag the points; "values" swaps in the raw fields */
.ed { position: absolute; }
.ed .node { fill: var(--paper); stroke: var(--signal); stroke-width: 1.6; }
.ed .node.hot { fill: var(--signal); }
.ed .node.hollow { fill: var(--panel); stroke-dasharray: 2 1.5; }
.ed .node.bend { fill: var(--panel); stroke-width: 1.3; }
.ed .node.bend.hot { fill: var(--signal); }
.ed .hit { fill: transparent; pointer-events: all; }
.ed .nodelabel { font-size: 10px; font-weight: var(--title-weight); text-anchor: middle; fill: var(--signal); pointer-events: none; }
.ed .nodelabel.hot { fill: var(--on-signal); }
.ed .nodelabel.off { fill: var(--ink-faint); }
.ed .readout {
    font-size: 11.5px; fill: var(--ink); font-variant-numeric: tabular-nums; pointer-events: none;
    paint-order: stroke; stroke: var(--paper); stroke-width: 3px; stroke-linejoin: round;
}
.ed .xbtn { position: absolute; right: 4px; top: 4px; z-index: 2; height: 17px; padding: 0 6px; font-size: 11px; opacity: 0.85; }
.ed .xbtn:hover { opacity: 1; }
.ed .vals { position: absolute; inset: 0; display: none; }
.ed.expanded .vals { display: block; }
.ed.expanded > svg { display: none; }

.sep { position: absolute; height: 1px; background: rgba(var(--ink-rgb), 0.2); }
.note { position: absolute; font-size: 11px; color: var(--ink-faint); white-space: nowrap; }
.note.wrap { white-space: normal; line-height: 1.35; }
.scale { position: absolute; height: ${px(controlHeight)}; line-height: ${px(controlHeight)}; font-size: 12.5px; color: var(--ink-faint);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.scale.on { color: var(--ink); font-weight: var(--title-weight); }

/* header: page tabs, then the program and file controls */
.pv-head {
    position: absolute; left: 0; right: 0; top: 0; height: ${px(headerHeight)};
    display: flex; align-items: center; gap: 6px; padding: 0 6px; box-sizing: border-box;
    background: var(--panel); border-bottom: 1px solid var(--edge);
    font-size: 13px;
}
.pv-head .brand { font-weight: var(--title-weight); font-size: 17px; letter-spacing: 0.02em; padding: 0 8px 0 4px; }
/* a full header doesn't squeeze the buttons (their labels would wrap out of them): the program name gives way instead */
.pv-head .btn { position: static; height: 22px; flex-shrink: 0; white-space: nowrap; }
.pv-head .pages { display: flex; }
.pv-head .pages .btn { border-radius: 0; margin-left: -1px; min-width: 64px; font-size: 13px; }
.pv-head .pages .btn:first-child { border-radius: var(--radius-sm) 0 0 2px; }
.pv-head .pages .btn:last-child { border-radius: 0 2px 2px 0; }
.pv-head .spacer { flex: 1; }
.pv-head .prog { display: flex; align-items: center; gap: 3px; min-width: 0; }
.pv-head .prog .name {
    width: 200px; min-width: 0; height: 20px; box-sizing: border-box; padding: 0 6px; border: 1px solid var(--edge); background: var(--paper);
    display: flex; align-items: center; font-size: 13px; cursor: pointer; white-space: nowrap; overflow: hidden;
}
.pv-head .prog .btn { width: 22px; padding: 0; }
.pv-head .btn.icon { width: 26px; padding: 0; font-size: 15px; }

/* status line: hover texts, or a hint for the page */
.pv-status {
    position: absolute; left: 0; right: 0; bottom: 0; height: ${px(statusHeight)};
    padding: 0 8px; box-sizing: border-box; display: flex; align-items: center;
    background: var(--panel); border-top: 1px solid var(--edge);
    font-size: 12.5px; font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.pv-status.idle { color: var(--ink-faint); font-size: 12px; }

/* menus */
.menu {
    position: absolute; z-index: 70; background: var(--paper); border: 1px solid var(--ink);
    padding: 2px 0; font-size: 12.5px; max-height: 560px; overflow-y: auto; min-width: 120px;
    box-shadow: var(--shadow);
}
.menu div { display: flex; align-items: center; box-sizing: border-box; min-height: 19px; padding: 0 12px 0 10px; white-space: nowrap; cursor: pointer; }
.menu div:hover { background: var(--signal); color: var(--on-signal); }
.menu div.cur { font-weight: var(--title-weight); }
.menu.cols { column-gap: 0; }
.menu.cols div { break-inside: avoid; }
.menu div.mh { min-height: 0; padding: 6px 12px 3px 10px; font-size: 11px; color: var(--ink-faint); cursor: default;
    text-transform: uppercase; letter-spacing: 0.06em; }
.menu div.mh:hover { background: none; color: var(--ink-faint); }
.menu.icons div { display: flex; align-items: center; }
.menu.icons .icw { width: 38px; flex: none; }

/* icons (Icons.res): strokes in the text colour */
.ic { display: block; height: 14px; width: auto; flex: none; overflow: visible;
    fill: none; stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; }
.ic .f { fill: currentColor; stroke: none; }
.ic .dash { stroke-dasharray: 2 2; stroke-width: 1.2; }
.ic text { fill: currentColor; stroke: none; font-size: 6.5px; font-weight: var(--title-weight); text-anchor: middle; }
.ic.bold { stroke-width: 2.1; height: 15px; }
.icw { display: inline-flex; align-items: center; gap: 2px; vertical-align: middle; }
.menu div:hover .hq { background: var(--paper); color: var(--signal); }

/* text entry */
.entry {
    position: absolute; z-index: 40; font: inherit; font-size: 12.5px; box-sizing: border-box;
    border: 1px solid var(--signal); background: var(--paper); color: var(--ink); padding: 0 3px; outline: none;
}

/* drawing surfaces */
.draw { position: absolute; cursor: crosshair; }

/* the sample a shape was made from: its name, what came of it, and its overview to drag along */

.drop {
    position: absolute; inset: 0; z-index: 100; display: none; align-items: center; justify-content: center;
    background: rgba(var(--signal-rgb), 0.55); color: var(--on-signal); font-size: 22px; font-weight: var(--title-weight);
}

.toast {
    position: absolute; left: 50%; bottom: 40px; transform: translateX(-50%); z-index: 90;
    background: var(--ink); color: var(--paper); padding: 5px 12px; font-size: 13px; border-radius: var(--radius-sm);
    display: none; max-width: 80%;
}
.toast.on { display: block; }

/* mod page: source chips (with a jack on the right), target chips (jack on the left) */
/* the picker's targets, under its title row: they scroll when they don't all fit */

/* dialogs */
.shade { position: absolute; inset: 0; z-index: 80; background: rgba(var(--ink-rgb), 0.35); display: flex; align-items: center; justify-content: center; }
.dlg {
    width: 460px; box-sizing: border-box; padding: 10px 14px 12px 14px; background: var(--panel);
    border: 1px solid var(--ink); border-radius: var(--radius); box-shadow: var(--shadow);
}
.dlg .dttl { font-weight: var(--title-weight); font-size: 15px; margin-bottom: 8px; }
.dlg .drow { display: flex; align-items: flex-start; gap: 8px; margin: 5px 0; font-size: 12px; color: var(--ink-soft); }
.dlg .drow span { width: 74px; padding-top: 3px; }
.dlg input, .dlg textarea {
    flex: 1; font: inherit; font-size: 13px; color: var(--ink); background: var(--paper);
    border: 1px solid var(--edge); padding: 2px 5px; outline: none; box-sizing: border-box;
}
.dlg input:focus, .dlg textarea:focus { border-color: var(--signal); }
.dlg textarea { height: 84px; resize: none; }
.dlg .dbtns { display: flex; justify-content: flex-end; gap: 6px; margin-top: 10px; }
.dlg .btn { position: static; min-width: 64px; }
.dlg .seg { display: flex; flex-wrap: wrap; }
.dlg .seg .btn { min-width: 0; padding: 0 6px; border-radius: 0; margin-left: -1px; }
.dlg .seg .btn.off { opacity: 0.45; pointer-events: none; }
.dlg .dnote { margin: 6px 0 6px 82px; font-size: 11.5px; line-height: 1.35; color: var(--ink-faint); }
.dlg .dnote + .btn { margin-left: 82px; }

/* the preset browser (PresetBrowser.res): sources and facets, the list, the details */
.brw {
    width: 1060px; height: 546px; box-sizing: border-box; display: flex; flex-direction: column;
    background: var(--panel); border: 1px solid var(--ink); border-radius: var(--radius); box-shadow: var(--shadow);
}
.brw ::-webkit-scrollbar, .picks::-webkit-scrollbar { width: 9px; }
.brw ::-webkit-scrollbar-thumb, .picks::-webkit-scrollbar-thumb { background: rgba(var(--edge-rgb), 0.45); border-radius: 4px; border: 2px solid transparent; background-clip: padding-box; }
.brw ::-webkit-scrollbar-track, .picks::-webkit-scrollbar-track { background: transparent; }
.brw-head { display: flex; align-items: center; gap: 10px; padding: 8px 10px 7px 12px; }
.brw-title { font-weight: var(--title-weight); font-size: 16px; }
.brw-search { flex: 1; position: relative; }
.brw-search input {
    display: block; width: 100%; height: 26px; box-sizing: border-box; padding: 0 26px 0 8px;
    font: inherit; font-size: 13.5px; color: var(--ink); background: var(--paper); border: 1px solid var(--edge); outline: none;
}
.brw-search input:focus { border-color: var(--signal); }
.brw-search input::placeholder { color: var(--ink-faint); }
.brw-x {
    position: absolute; right: 3px; top: 3px; width: 20px; height: 20px; display: none; padding: 0;
    border: none; background: transparent; font: inherit; font-size: 12px; color: var(--ink-faint); cursor: pointer;
}
.brw-x.on { display: block; }
.brw-x:hover { color: var(--ink); }
.brw-count { width: 84px; text-align: right; font-size: 12px; color: var(--ink-faint); font-variant-numeric: tabular-nums; }
.brw-body { flex: 1; min-height: 0; display: flex; gap: 8px; padding: 0 10px; }

.brw-side {
    width: 188px; flex: none; overflow-y: auto; padding: 2px 0 8px; border-radius: var(--radius-sm);
    background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge);
}
.brw-shead { padding: 7px 8px 2px; font-size: 11.5px; font-weight: var(--title-weight); color: var(--ink-faint); }
.brw-srow { display: flex; align-items: center; gap: 6px; height: 22px; padding: 0 8px; font-size: 13px; cursor: pointer; white-space: nowrap; }
.brw-srow:hover { background: var(--panel-hi); }
.brw-srow.on { background: var(--signal); color: var(--on-signal); }
.brw-slabel { flex: 1; overflow: hidden; text-overflow: ellipsis; }
.brw-srow.bad .brw-slabel { text-decoration: line-through; opacity: 0.6; }
.brw-srm { display: none; font-size: 11px; padding: 0 2px; }
.brw-srow:hover .brw-srm { display: inline; }
.brw-open { font-size: 12.5px; color: var(--ink-soft); }
.brw-addfolder { display: block; box-sizing: border-box; width: calc(100% - 12px); margin: 2px 6px 4px; height: 22px;
  font-size: 12px; }
.brw-n { font-size: 11px; color: var(--ink-faint); font-variant-numeric: tabular-nums; }
.on > .brw-n { color: inherit; opacity: 0.75; }
.brw-facet { display: flex; flex-direction: column; }
.brw-facet .brw-fv {
    display: flex; justify-content: space-between; gap: 6px; height: 21px; line-height: 21px; padding: 0 8px 0 14px;
    font-size: 12.5px; cursor: pointer; white-space: nowrap;
}
.brw-facet .brw-fv > span:first-child { overflow: hidden; text-overflow: ellipsis; }
.brw-chips { display: flex; flex-wrap: wrap; gap: 3px; padding: 3px 8px; }
.brw-chips .brw-fv {
    display: inline-flex; gap: 4px; height: 18px; line-height: 18px; padding: 0 6px; border-radius: 9px;
    font-size: 11.5px; cursor: pointer; white-space: nowrap; background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge);
}
.brw-fv:hover { background: var(--panel-hi); }
.brw-fv.on { background: var(--signal); color: var(--on-signal); box-shadow: none; }

.brw-list { flex: 1; min-width: 0; overflow-y: auto; position: relative; background: var(--paper); border: 1px solid var(--edge); }
.brw-row {
    display: flex; align-items: center; gap: 8px; height: 24px; padding: 0 8px 0 4px; box-sizing: border-box;
    font-size: 13px; cursor: pointer; white-space: nowrap; border-bottom: 1px solid rgba(var(--ink-rgb), 0.07);
}
.brw-row:hover { background: rgba(var(--signal-rgb), 0.08); }
.brw-row.sel { background: var(--signal); color: var(--on-signal); }
.brw-num { width: 18px; flex: none; text-align: right; font-size: 11px; color: var(--ink-faint); font-variant-numeric: tabular-nums; }
.brw-name { flex: 1 1 160px; min-width: 80px; overflow: hidden; text-overflow: ellipsis; }
.brw-row.cur .brw-name { font-weight: var(--title-weight); }
.brw-row.cur .brw-num { color: var(--signal); font-weight: var(--title-weight); }
.brw-cat { width: 64px; flex: none; font-size: 12px; color: var(--ink-soft); overflow: hidden; text-overflow: ellipsis; }
.brw-tags { width: 200px; flex: none; display: flex; gap: 3px; overflow: hidden; }
.brw-list.nosrc .brw-tags { width: 290px; }
.brw-src { width: 96px; flex: none; text-align: right; font-size: 11.5px; color: var(--ink-faint); overflow: hidden; text-overflow: ellipsis; }
.brw-row.sel .brw-num, .brw-row.sel .brw-cat, .brw-row.sel .brw-src { color: inherit; opacity: 0.8; }
.brw-chip {
    flex: none; height: 16px; line-height: 16px; padding: 0 6px; border-radius: 8px; font-size: 11px; cursor: pointer;
    background: rgba(var(--ink-rgb), 0.08); color: var(--ink-soft);
}
.brw-chip:hover { background: rgba(var(--signal-rgb), 0.2); color: var(--ink); }
.brw-chip.on { background: var(--signal); color: var(--on-signal); }
.brw-row.sel .brw-chip { background: rgba(var(--paper-rgb), 0.22); color: var(--on-signal); }
.brw-row.sel .brw-chip.on { background: var(--on-signal); color: var(--signal); }
.brw-more { padding: 10px; text-align: center; font-size: 12.5px; color: var(--ink-faint); }
.brw-none { padding-top: 70px; display: flex; flex-direction: column; align-items: center; gap: 12px; font-size: 14px; color: var(--ink-soft); }
.brw-none .btn { position: static; }

.brw-info { width: 252px; flex: none; overflow-y: auto; padding: 0 2px 8px 4px; }
.brw-iname { margin: 1px 0 3px; font-weight: var(--title-weight); font-size: 17px; line-height: 1.2; overflow-wrap: anywhere; }
.brw-isub { margin-bottom: 8px; font-size: 12px; color: var(--ink-soft); }
.brw-itags { display: flex; flex-wrap: wrap; gap: 3px; margin-bottom: 9px; }
.brw-idesc { font-size: 12.5px; line-height: 1.42; white-space: pre-wrap; user-select: text; -webkit-user-select: text; }
.brw-ihead { margin: 10px 0 2px; font-size: 11.5px; font-weight: var(--title-weight); color: var(--ink-faint); }
.brw-itext { font-size: 12px; line-height: 1.35; color: var(--ink-soft); }
.brw-empty { padding-top: 20px; font-size: 12.5px; color: var(--ink-faint); }

.brw-foot { display: flex; align-items: center; gap: 8px; padding: 7px 10px 8px; }
.brw-foot .tg { position: static; height: 22px; padding: 0 8px 0 5px; }
.brw-hint { flex: 1; font-size: 11.5px; color: var(--ink-faint); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.brw-foot .btn { position: static; height: 22px; min-width: 72px; }
.brw-load { font-weight: var(--title-weight); }
.brw-load.off { opacity: 0.45; pointer-events: none; }

/* A single-line label (Web.setLabel; buttons get theirs that way): trimmed to the height of its
   capitals, so that a flex box centres the letters themselves rather than the font's line box, which
   sits a pixel off in most fonts (Bahnschrift high, Segoe UI low). Clipped sideways only, so that
   nothing above or below the capitals is cut. */
.lbl {
    display: block; min-width: 0; line-height: 1; text-box: trim-both cap alphabetic;
    white-space: nowrap; overflow-x: clip; overflow-y: visible; text-overflow: ellipsis;
}

.p:focus-visible, .btn:focus-visible, .tg:focus-visible, .knob:focus-visible { outline: 2px solid var(--signal); outline-offset: 1px; }

/* a rotary knob (Controls.knob): the label over the dial, the value under it */
.knob {
    position: absolute; box-sizing: border-box; display: flex; flex-direction: column; align-items: center;
    cursor: ns-resize; border-radius: var(--radius-sm); padding-top: 1px;
}
.knob:hover, .knob.drag { background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge); }
.knob .l { font-size: 11px; line-height: 13px; color: var(--ink-soft); white-space: nowrap; text-transform: var(--label-case); }
.knob .v { font-size: 12px; line-height: 15px; font-variant-numeric: tabular-nums; white-space: nowrap; }
.knob .dial { display: block; overflow: visible; }
.knob .dial .track { fill: none; stroke: rgba(var(--ink-rgb), 0.15); stroke-width: 0.17; stroke-linecap: round; }
.knob .dial .fill { fill: none; stroke: var(--signal); stroke-width: 0.17; stroke-linecap: round; }
.knob .dial .cap { fill: var(--paper); stroke: var(--edge); stroke-width: 0.05; }
.knob .dial .pointer { stroke: var(--ink); stroke-width: 0.1; stroke-linecap: round; }

/* level meters (Meter.res): a bar per channel, filled from the bottom, with a peak line */
.meter { position: absolute; display: flex; gap: 2px; box-sizing: border-box; padding: 1px; border-radius: var(--radius-sm);
    background: rgba(var(--ink-rgb), 0.12); box-shadow: inset 0 0 0 1px var(--tile-edge); }
.meter .bar { position: relative; flex: 1; overflow: hidden; }
.meter .bar i { position: absolute; left: 0; right: 0; bottom: 0; background: var(--signal); }
.meter .bar b { position: absolute; left: 0; right: 0; height: 1px; background: var(--ink); }
.meter .bar.hot i { background: var(--mod); }

/* the dirty mark beside the preset name */
.pv-head .prog .name.dirty::after { content: " *"; color: var(--ink-faint); }
`

// Everything, for the view's stylesheet.
let all = () => [css, ...extras]->Array.join("\n")
