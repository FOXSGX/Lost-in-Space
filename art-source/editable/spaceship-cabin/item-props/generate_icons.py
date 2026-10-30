from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
colors={'medical':'#ef8585','oxygen':'#75d1ea','battery':'#7fdfb1','sample':'#b49ae8','penguin':'#8de9ff','bubble':'#c5a4ff','board':'#ffd36e','hologram':'#ff9bd7','smoke':'#ff7fd1','core':'#7fdfb1','freight':'#ffd36e','coolant':'#75d1ea'}
shapes={
'medical':'<rect x="14" y="31" width="100" height="76" rx="14"/><path d="M47 18h34v15H47z"/><path d="M54 47h20v48H54zM40 61h48v20H40z" fill="#f8f2dd"/>',
'oxygen':'<rect x="37" y="24" width="54" height="94" rx="23"/><path d="M49 12h30v15H49zM40 7h48v9H40z"/><path d="M47 63h34v26H47z" fill="#e7efe2"/>',
'battery':'<rect x="18" y="29" width="92" height="77" rx="12"/><path d="M40 15h15v17H40zM74 15h15v17H74z"/><path d="M68 41L47 72h16l-5 25 25-36H66z" fill="#f6f6dc"/>',
'sample':'<path d="M64 11l33 27 12 42-45 39-45-39 12-42z"/><path d="M64 12v105M31 38l33 79L97 38M20 80h88" fill="none" stroke="#f1e1fa" stroke-width="5"/>',
'penguin':'<ellipse cx="64" cy="69" rx="35" ry="47"/><ellipse cx="64" cy="76" rx="22" ry="33" fill="#eff4e9"/><circle cx="52" cy="40" r="5" fill="#153345"/><circle cx="76" cy="40" r="5" fill="#153345"/><path d="M54 52h20L64 66z" fill="#ffc472"/>',
'bubble':'<circle cx="64" cy="64" r="46" fill-opacity=".5"/><circle cx="64" cy="64" r="46" fill="none" stroke="#e7defa" stroke-width="7"/><path d="M34 55a33 33 0 0 1 30-24" fill="none" stroke="#fff3e4" stroke-width="8"/>',
'board':'<rect x="10" y="44" width="108" height="42" rx="21" transform="rotate(-23 64 64)"/><path d="M43 50l11 25M71 39l11 25" fill="none" stroke="#153345" stroke-width="8"/>',
'hologram':'<path d="M29 108l35-25 35 25z"/><circle cx="64" cy="35" r="18"/><path d="M38 84V68q0-18 26-18t26 18v16z" fill-opacity=".55"/><path d="M31 101h66M37 94h54" stroke="#f7e3f1" stroke-width="5"/>',
'smoke':'<rect x="41" y="54" width="46" height="62" rx="8"/><path d="M50 54V42q-25-8-12-23 8-11 25 2 17-26 30-9 12 17-12 30v12z" fill-opacity=".65"/>',
}
for key, color in colors.items():
    source=shapes.get(key,shapes['battery' if key=='core' else ('oxygen' if key=='coolant' else 'medical')])
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><g fill="{color}">{source}</g></svg>\n'
    for base in [HERE/'icons',ROOT/'game/assets/items/icons']:
        base.mkdir(parents=True,exist_ok=True); (base/(key+'.svg')).write_text(svg,encoding='utf-8')
print('ITEM_ICONS:',len(colors))
