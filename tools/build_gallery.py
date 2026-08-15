#!/usr/bin/env python3
"""Assemble the design proposals into one self-contained review page."""
import base64
import html
import json
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROP = os.path.join(REPO, 'docs', 'design-proposals')
WEB = os.path.join(PROP, 'web')
OUT = os.path.join(PROP, 'gallery.html')

SLUGS = {
    'Chat management': 'chat-management',
    'Search': 'search',
    'Links and previews': 'web-and-links',
    'Premium': 'premium',
    'Stickers and custom emoji': 'stickers-emoji',
    'Stories': 'stories',
    'Profiles and identity': 'users-contacts',
    'Reactions on a message': 'reactions',
    'Stars and payments': 'stars-payments',
    'Chat list organisation': 'chat-list',
    'New message content kinds': 'messages-content',
    'Saved Messages': 'saved-messages',
    'Forum topics': 'forums',
    'Bots': 'bots',
    'Privacy and security': 'privacy-security',
    'Login and accounts': 'auth-account',
    'Media and downloads': 'media-download',
}


def slug_for(theme, options):
    if theme in SLUGS:
        return SLUGS[theme]
    for opt in options:
        name = opt.get('svgFile') or ''
        m = re.match(r'(.+)-[a-z]\.svg$', name)
        if m:
            return m.group(1)
    return re.sub(r'[^a-z0-9]+', '-', theme.lower()).strip('-')


def img_uri(svg_name):
    jpg = os.path.join(WEB, svg_name.replace('.svg', '.jpg'))
    if not os.path.exists(jpg):
        return None
    with open(jpg, 'rb') as handle:
        return 'data:image/jpeg;base64,' + base64.b64encode(handle.read()).decode()


def esc(text):
    return html.escape(text or '')


def pick_recommended(rec, options):
    """Which option letter the recommendation names first."""
    if not rec:
        return None
    for opt in options:
        letter = opt.get('letter') or ''
        if re.search(r'\bOption\s+' + re.escape(letter) + r'\b', rec):
            return letter
    for opt in options:
        letter = opt.get('letter') or ''
        if re.search(r'\b' + re.escape(letter) + r'\b', rec[:40]):
            return letter
    return None


def main():
    themes = json.load(open(os.path.join(PROP, 'index.json')))
    themes.sort(key=lambda t: -len(t.get('options') or []))

    total_options = sum(len(t.get('options') or []) for t in themes)
    total_cannot = sum(len(t.get('cannotFit') or []) for t in themes)

    nav = []
    sections = []
    cannot_blocks = []

    for theme in themes:
        options = theme.get('options') or []
        slug = slug_for(theme.get('theme', ''), options)
        title = theme.get('theme', '').split('—')[0].strip()
        rec = theme.get('recommendation') or ''
        best = pick_recommended(rec, options)

        nav.append('<a href="#%s">%s</a>' % (slug, esc(title)))

        cards = []
        for opt in options:
            uri = img_uri(opt.get('svgFile') or '')
            letter = opt.get('letter') or ''
            chosen = (letter == best)
            shot = ('<img src="%s" alt="%s" loading="lazy">' % (uri, esc(opt.get('name')))
                    if uri else '<div class="missing">not rendered</div>')
            cards.append(
                '<figure class="opt%s">'
                '<div class="screen">%s</div>'
                '<figcaption>'
                '<p class="tag"><span class="letter">%s</span>%s</p>'
                '<h4>%s</h4>'
                '<p class="line">%s</p>'
                '<p class="cost"><span>gives up</span>%s</p>'
                '</figcaption></figure>' % (
                    ' chosen' if chosen else '',
                    shot,
                    esc(letter),
                    '<span class="rec">recommended</span>' if chosen else '',
                    esc(opt.get('name')),
                    esc(opt.get('oneLine')),
                    esc(opt.get('tradeoff')),
                ))

        sections.append(
            '<section id="%s" class="theme">'
            '<header class="theme-head"><h3>%s</h3><p class="count">%d options</p></header>'
            '<div class="opts">%s</div>'
            '%s'
            '</section>' % (
                slug, esc(title), len(options), ''.join(cards),
                ('<div class="verdict"><h5>Why this one</h5><p>%s</p></div>' % esc(rec)) if rec else '',
            ))

        cannot = theme.get('cannotFit') or []
        if cannot:
            items = ''.join('<li>%s</li>' % esc(c) for c in cannot)
            cannot_blocks.append(
                '<div class="wont"><h4>%s</h4><ul>%s</ul></div>' % (esc(title), items))

    doc = TEMPLATE
    for key, value in (
            ('__NAV__', ''.join(nav)),
            ('__SECTIONS__', ''.join(sections)),
            ('__CANNOT__', ''.join(cannot_blocks)),
            ('__THEMES__', str(len(themes))),
            ('__OPTIONS__', str(total_options)),
            ('__CANNOT_COUNT__', str(total_cannot))):
        doc = doc.replace(key, value)
    with open(OUT, 'w', encoding='utf-8') as handle:
        handle.write(doc)
    print('wrote %s (%.1f MB)' % (OUT, os.path.getsize(OUT) / 1e6))


TEMPLATE = r'''<title>Fitting Modern Telegram Into 2013</title>
<style>
:root{
  --ground:#e9edf2;
  --panel:#ffffff;
  --panel-2:#f4f6f9;
  --ink:#141a21;
  --ink-2:#5a6673;
  --ink-3:#8b97a5;
  --rule:#d3dae3;
  --chrome-top:#7699c0;
  --chrome-bot:#42678f;
  --link:#2f6ba8;
  --brass:#a8741d;
  --brass-soft:#f6ecd8;
  --shadow:0 1px 2px rgba(20,26,33,.08), 0 8px 24px rgba(20,26,33,.06);
  --display:"Helvetica Neue",Helvetica,Arial,sans-serif;
  --body:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  --mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --ground:#12171d;
    --panel:#1a2129;
    --panel-2:#212a34;
    --ink:#e6ecf3;
    --ink-2:#a3b0bf;
    --ink-3:#75828f;
    --rule:#2b353f;
    --chrome-top:#5d7ea3;
    --chrome-bot:#35526f;
    --link:#7fb2e0;
  
    --brass:#d9a94e;
    --brass-soft:#2e2718;
    --shadow:0 1px 2px rgba(0,0,0,.4), 0 10px 30px rgba(0,0,0,.35);
  }
}
:root[data-theme="dark"]{
  --ground:#12171d;
  --panel:#1a2129;
  --panel-2:#212a34;
  --ink:#e6ecf3;
  --ink-2:#a3b0bf;
  --ink-3:#75828f;
  --rule:#2b353f;
  --chrome-top:#5d7ea3;
  --chrome-bot:#35526f;
  --link:#7fb2e0;
  --brass:#d9a94e;
  --brass-soft:#2e2718;
  --shadow:0 1px 2px rgba(0,0,0,.4), 0 10px 30px rgba(0,0,0,.35);
}
*{box-sizing:border-box}
body{
  margin:0;background:var(--ground);color:var(--ink);
  font-family:var(--body);font-size:16px;line-height:1.6;
  -webkit-font-smoothing:antialiased;
}
.wrap{max-width:1180px;margin:0 auto;padding:0 24px 96px}

.masthead{
  background:linear-gradient(180deg,var(--chrome-top),var(--chrome-bot));
  color:#fff;padding:56px 24px 44px;margin-bottom:40px;
  border-bottom:1px solid rgba(0,0,0,.25);
}
.masthead .inner{max-width:1180px;margin:0 auto}
.masthead h1{
  font-family:var(--display);font-weight:700;letter-spacing:-.022em;
  font-size:clamp(30px,4.4vw,50px);line-height:1.05;margin:0 0 14px;
  text-wrap:balance;text-shadow:0 1px 0 rgba(0,0,0,.28);
}
.masthead p{margin:0;max-width:60ch;color:rgba(255,255,255,.9);font-size:17px}
.stats{display:flex;flex-wrap:wrap;gap:28px;margin-top:26px;padding-top:22px;
  border-top:1px solid rgba(255,255,255,.22)}
.stat b{display:block;font-family:var(--mono);font-size:26px;font-variant-numeric:tabular-nums;
  font-weight:600;letter-spacing:-.02em}
.stat span{font-size:12px;text-transform:uppercase;letter-spacing:.09em;color:rgba(255,255,255,.75)}

.toc{
  background:var(--panel);border:1px solid var(--rule);border-radius:6px;
  padding:18px 20px;margin-bottom:44px;box-shadow:var(--shadow);
}
.toc h2{font-size:11px;text-transform:uppercase;letter-spacing:.12em;color:var(--ink-3);
  margin:0 0 12px;font-weight:600}
.toc div{display:flex;flex-wrap:wrap;gap:6px 20px}
.toc a{color:var(--link);text-decoration:none;font-size:14.5px;border-bottom:1px solid transparent}
.toc a:hover,.toc a:focus{border-bottom-color:currentColor}

.theme{margin:0 0 64px;scroll-margin-top:20px}
.theme-head{display:flex;align-items:baseline;gap:14px;
  border-bottom:2px solid var(--ink);padding-bottom:8px;margin-bottom:26px}
.theme-head h3{font-family:var(--display);font-weight:700;letter-spacing:-.02em;
  font-size:27px;margin:0;text-wrap:balance}
.count{margin:0;font-family:var(--mono);font-size:12px;color:var(--ink-3);
  text-transform:uppercase;letter-spacing:.08em}

.opts{display:grid;grid-template-columns:repeat(auto-fit,minmax(268px,1fr));gap:26px}
figure{margin:0;background:var(--panel);border:1px solid var(--rule);border-radius:6px;
  overflow:hidden;box-shadow:var(--shadow);display:flex;flex-direction:column}
figure.chosen{border-color:var(--brass);box-shadow:0 0 0 1px var(--brass),var(--shadow)}
.screen{background:var(--panel-2);padding:16px;display:flex;justify-content:center;
  border-bottom:1px solid var(--rule)}
.screen img{width:100%;max-width:280px;height:auto;display:block;border-radius:3px;
  border:1px solid rgba(0,0,0,.28)}
.missing{color:var(--ink-3);font-family:var(--mono);font-size:13px;padding:60px 0}
figcaption{padding:16px 18px 20px;display:flex;flex-direction:column;gap:8px;flex:1}
.tag{margin:0;display:flex;align-items:center;gap:9px}
.letter{font-family:var(--mono);font-weight:600;font-size:12px;color:var(--ink-2);
  background:var(--panel-2);border:1px solid var(--rule);border-radius:3px;
  padding:1px 7px;letter-spacing:.04em}
.rec{font-size:10.5px;text-transform:uppercase;letter-spacing:.1em;font-weight:700;
  color:var(--brass);background:var(--brass-soft);border-radius:3px;padding:3px 8px}
figcaption h4{font-family:var(--display);font-weight:700;letter-spacing:-.012em;
  font-size:18.5px;margin:0;text-wrap:balance}
.line{margin:0;font-size:14.5px;color:var(--ink-2);line-height:1.55}
.cost{margin:6px 0 0;font-size:13.5px;color:var(--ink-3);line-height:1.5;
  padding-top:10px;border-top:1px solid var(--rule)}
.cost span{display:block;font-family:var(--mono);font-size:10.5px;text-transform:uppercase;
  letter-spacing:.1em;color:var(--ink-3);margin-bottom:3px}

.verdict{margin-top:22px;background:var(--panel);border:1px solid var(--rule);
  border-left:3px solid var(--brass);border-radius:0 5px 5px 0;padding:16px 20px}
.verdict h5{margin:0 0 6px;font-family:var(--mono);font-size:10.5px;text-transform:uppercase;
  letter-spacing:.11em;color:var(--brass);font-weight:600}
.verdict p{margin:0;font-size:15px;color:var(--ink-2);max-width:78ch}

.appendix{margin-top:80px;padding-top:36px;border-top:2px solid var(--ink)}
.appendix > h2{font-family:var(--display);font-weight:700;letter-spacing:-.02em;
  font-size:29px;margin:0 0 8px}
.appendix > p{margin:0 0 30px;color:var(--ink-2);max-width:68ch}
.wont{background:var(--panel);border:1px solid var(--rule);border-radius:6px;
  padding:16px 20px;margin-bottom:14px}
.wont h4{margin:0 0 8px;font-family:var(--display);font-size:16.5px;font-weight:700;
  letter-spacing:-.01em}
.wont ul{margin:0;padding-left:20px;display:flex;flex-direction:column;gap:6px}
.wont li{font-size:14px;color:var(--ink-2);line-height:1.5}

@media (max-width:640px){
  .masthead{padding:40px 20px 32px}
  .wrap{padding:0 16px 64px}
  .opts{grid-template-columns:1fr}
}
</style>

<header class="masthead"><div class="inner">
  <h1>Fitting modern Telegram into a 2013 phone</h1>
  <p>Two hundred and eighty-three capabilities exist in the API but have nowhere to live in this
  interface, because the surfaces they were designed for did not exist yet. These are the drawn
  options, grouped by the question each one answers. Every mockup is 320&times;480 points, built from
  the real 2013 artwork and the measured metrics, so whatever is chosen can be built as drawn.</p>
  <div class="stats">
    <div class="stat"><b>__THEMES__</b><span>questions</span></div>
    <div class="stat"><b>__OPTIONS__</b><span>options drawn</span></div>
    <div class="stat"><b>__CANNOT_COUNT__</b><span>ruled out</span></div>
  </div>
</div></header>

<div class="wrap">
  <nav class="toc"><h2>Jump to</h2><div>__NAV__</div></nav>
  __SECTIONS__

  <section class="appendix">
    <h2>What will not fit</h2>
    <p>Recorded rather than quietly dropped. An iPhone 4S has a 320&times;480 screen, 512&nbsp;MB of
    memory and one core; iOS 6 has no collection views, no blur, no interactive dismissal and only a
    primitive web view. These are the things that ran into that wall.</p>
    __CANNOT__
  </section>
</div>
'''

if __name__ == '__main__':
    main()
