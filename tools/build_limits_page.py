#!/usr/bin/env python3
"""Build the page explaining what the hardware will not allow."""
import base64
import glob
import html
import json
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROP = os.path.join(REPO, 'docs', 'design-proposals')
WEB = os.path.join(PROP, 'web')
OUT = os.path.join(PROP, 'limits-ru.html')

CAUSES = [
    {
        'id': 'memory',
        'name': '512 МБ памяти на всё',
        'count': 18,
        'what': 'iPhone 4S делит 512 МБ между системой и приложением. Реально нам достаётся около '
                '40–60 МБ, дальше система убивает процесс без предупреждения.',
        'hits': 'Сетки миниатюр, длинные ленты медиа, десятки одновременно живых превью, кэши поверх кэшей.',
        'do': 'Плитки перерабатываются вручную через TGViewRecycler, миниатюры уменьшаются до показа, '
              'за пределами экрана память отдаётся сразу. Видно меньше за раз — зато не падает.',
        'shot': None,
    },
    {
        'id': 'gestures',
        'name': 'Нет интерактивных жестов и переходов',
        'count': 18,
        'what': 'В iOS 6 нет ни интерактивного закрытия свайпом, ни кастомных переходов между экранами, '
                'ни жеста «потянуть, чтобы закрыть». Есть только push и модальное окно.',
        'hits': 'Истории, просмотрщик медиа, любые шторки и карточки, которые сегодня закрываются свайпом вниз.',
        'do': 'Панель навигации остаётся на месте, и выход — это кнопка Back. Менее эффектно, но из экрана '
              'всегда есть выход, а это важнее.',
        'shot': 'limit-stories',
    },
    {
        'id': 'web',
        'name': 'Только UIWebView',
        'count': 16,
        'what': 'WKWebView появился в iOS 8. У нас есть только старый UIWebView: медленный, с ограниченным '
                'JavaScript, без нормального управления памятью.',
        'hits': 'Instant View, веб-приложения ботов, платёжные формы, авторизация через веб.',
        'do': 'Превью ссылки рисуем сами внутри пузыря — это наш код и он быстрый. Сама статья открывается '
              'в системном браузере.',
        'shot': 'limit-instantview',
    },
    {
        'id': 'payments',
        'name': 'Нет платёжного стека',
        'count': 12,
        'what': 'Встроенные покупки требуют StoreKit и аккаунта разработчика, которых у этой сборки нет. '
                'Оплата картой требует современного веб-вида.',
        'hits': 'Покупка Premium, звёзды, подарки, подписки на каналы, оплата в ботах.',
        'do': 'Всё платёжное показываем, но не продаём: баланс, история операций, что даёт Premium и какие '
              'лимиты он поднимает. Покупка — в другом клиенте, статус подтянется сюда.',
        'shot': 'limit-payments',
    },
    {
        'id': 'animation',
        'name': 'Одно ядро A5 на анимацию',
        'count': 11,
        'what': 'Анимированные стикеры — это Lottie: векторная сцена, которую надо просчитывать каждый кадр. '
                'Одно ядро тянет одну такую сцену, не шестнадцать.',
        'hits': 'Сетки анимированных стикеров, анимированные эмодзи в тексте, эффекты больших реакций, '
                'видео-стикеры WebM.',
        'do': 'В сетке показываем первый кадр как статичную картинку. Анимируется ровно один стикер и только '
              'пока его держат — в этот момент ничего больше не двигается.',
        'shot': 'limit-stickers',
    },
    {
        'id': 'video',
        'name': 'Нет аппаратного кодирования видео',
        'count': 10,
        'what': 'A5 умеет проигрывать H.264, но кодировать его на лету практически не может. Современные '
                'кодеки вроде HEVC и VP9 не поддерживаются вовсе.',
        'hits': 'Съёмка видео-историй, кружки видеосообщений на запись, стриминг, живые трансляции.',
        'do': 'Проигрывание — да, там где кодек знакомый. Запись видео в новых форматах — нет.',
        'shot': None,
    },
    {
        'id': 'charts',
        'name': 'Нет графического движка под интерактивные графики',
        'count': 9,
        'what': 'Графики Telegram — это зум, панорамирование, двуручковый выбор диапазона и тултипы. Всё это '
                'непрерывно пересчитывает векторный путь из тысяч точек на каждом кадре.',
        'hits': 'Статистика каналов и групп, графики бустов, аналитика.',
        'do': 'Цифры показываем таблицей, динамику — простой столбчатой диаграммой, которая перерисовывается '
              'только при изменении данных. Читается так же, интерактива нет.',
        'shot': 'limit-statistics',
    },
]


def img(name):
    path = os.path.join(WEB, name + '.jpg')
    if not os.path.exists(path):
        return None
    with open(path, 'rb') as handle:
        return 'data:image/jpeg;base64,' + base64.b64encode(handle.read()).decode()


def esc(s):
    return html.escape(s or '')


def main():
    items = []
    for c in CAUSES:
        uri = img(c['shot']) if c['shot'] else None
        shot = ('<figure class="shot"><img src="%s" alt="%s" loading="lazy">'
                '<figcaption>Слева — как это работает в современном клиенте. '
                'Справа — что получается у нас.</figcaption></figure>' % (uri, esc(c['name']))) if uri else ''
        items.append(
            '<section class="cause" id="%s">'
            '<header><h3>%s</h3><span class="n">%d</span></header>'
            '<div class="grid">'
            '<div><h4>В чём упираемся</h4><p>%s</p></div>'
            '<div><h4>Что это задевает</h4><p>%s</p></div>'
            '<div class="ok"><h4>Что делаем вместо</h4><p>%s</p></div>'
            '</div>%s</section>' % (
                c['id'], esc(c['name']), c['count'],
                esc(c['what']), esc(c['hits']), esc(c['do']), shot))

    doc = TEMPLATE.replace('__ITEMS__', ''.join(items))
    with open(OUT, 'w', encoding='utf-8') as handle:
        handle.write(doc)
    print('wrote %s (%.1f MB)' % (OUT, os.path.getsize(OUT) / 1e6))


TEMPLATE = r'''<title>Seven Walls</title>
<style>
:root{
  --ground:#e9edf2; --panel:#fff; --panel-2:#f4f6f9;
  --ink:#141a21; --ink-2:#5a6673; --ink-3:#8b97a5; --rule:#d3dae3;
  --chrome-top:#7699c0; --chrome-bot:#42678f;
  --brass:#a8741d; --brass-soft:#fdf6e6; --green:#2e7d4f; --green-soft:#eaf4ee;
  --shadow:0 1px 2px rgba(20,26,33,.08),0 8px 24px rgba(20,26,33,.06);
  --display:"Helvetica Neue",Helvetica,Arial,sans-serif;
  --body:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  --mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --ground:#12171d; --panel:#1a2129; --panel-2:#212a34;
  --ink:#e6ecf3; --ink-2:#a3b0bf; --ink-3:#75828f; --rule:#2b353f;
  --chrome-top:#5d7ea3; --chrome-bot:#35526f;
  --brass:#d9a94e; --brass-soft:#2e2718; --green:#6cc191; --green-soft:#17281f;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 10px 30px rgba(0,0,0,.35);
}}
:root[data-theme="dark"]{
  --ground:#12171d; --panel:#1a2129; --panel-2:#212a34;
  --ink:#e6ecf3; --ink-2:#a3b0bf; --ink-3:#75828f; --rule:#2b353f;
  --chrome-top:#5d7ea3; --chrome-bot:#35526f;
  --brass:#d9a94e; --brass-soft:#2e2718; --green:#6cc191; --green-soft:#17281f;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 10px 30px rgba(0,0,0,.35);
}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);font-family:var(--body);
  font-size:16px;line-height:1.62;-webkit-font-smoothing:antialiased}
.wrap{max-width:1080px;margin:0 auto;padding:0 24px 96px}
.masthead{background:linear-gradient(180deg,var(--chrome-top),var(--chrome-bot));color:#fff;
  padding:56px 24px 44px;margin-bottom:40px;border-bottom:1px solid rgba(0,0,0,.25)}
.masthead .inner{max-width:1080px;margin:0 auto}
.masthead h1{font-family:var(--display);font-weight:700;letter-spacing:-.022em;
  font-size:clamp(30px,4.4vw,48px);line-height:1.06;margin:0 0 16px;text-wrap:balance;
  text-shadow:0 1px 0 rgba(0,0,0,.28)}
.masthead p{margin:0 0 10px;max-width:62ch;color:rgba(255,255,255,.92);font-size:17px}
.cause{background:var(--panel);border:1px solid var(--rule);border-radius:7px;
  box-shadow:var(--shadow);margin-bottom:26px;overflow:hidden}
.cause > header{display:flex;align-items:center;gap:14px;padding:18px 22px;
  border-bottom:1px solid var(--rule);background:var(--panel-2)}
.cause h3{font-family:var(--display);font-weight:700;letter-spacing:-.018em;font-size:22px;
  margin:0;flex:1;text-wrap:balance}
.n{font-family:var(--mono);font-size:13px;font-variant-numeric:tabular-nums;color:var(--ink-3);
  border:1px solid var(--rule);border-radius:20px;padding:3px 11px;white-space:nowrap}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:0}
.grid > div{padding:18px 22px;border-right:1px solid var(--rule)}
.grid > div:last-child{border-right:0}
.grid h4{margin:0 0 7px;font-family:var(--mono);font-size:10.5px;text-transform:uppercase;
  letter-spacing:.11em;color:var(--ink-3);font-weight:600}
.grid p{margin:0;font-size:14.5px;color:var(--ink-2)}
.grid .ok{background:var(--green-soft)}
.grid .ok h4{color:var(--green)}
.grid .ok p{color:var(--ink)}
.shot{margin:0;padding:20px 22px 22px;border-top:1px solid var(--rule);background:var(--panel-2)}
.shot img{width:100%;height:auto;display:block;border-radius:5px;border:1px solid var(--rule)}
.shot figcaption{margin-top:10px;font-size:12.5px;color:var(--ink-3);font-family:var(--mono)}
.closing{margin-top:44px;background:var(--brass-soft);border:1px solid var(--brass);
  border-left:3px solid var(--brass);border-radius:0 6px 6px 0;padding:20px 24px}
.closing h2{margin:0 0 8px;font-family:var(--display);font-size:20px;font-weight:700;
  letter-spacing:-.015em;color:var(--brass)}
.closing p{margin:0;font-size:15px;color:var(--ink-2);max-width:76ch}
@media (max-width:640px){.masthead{padding:40px 20px 32px}.wrap{padding:0 16px 64px}
  .grid > div{border-right:0;border-bottom:1px solid var(--rule)}}
</style>

<header class="masthead"><div class="inner">
  <h1>Семь стен, в которые упирается железо</h1>
  <p>В каталоге 115 возможностей помечены как невыполнимые. Это не 115 разных проблем —
  это семь физических ограничений iPhone 4S и iOS 6, каждое из которых задевает свою группу функций.</p>
  <p>Ниже — что именно мешает, что из-за этого недоступно, и что мы делаем вместо. Там, где разница
  видна глазом, добавлено сравнение: слева современный клиент, справа наш.</p>
</div></header>

<div class="wrap">
  __ITEMS__
  <section class="closing">
    <h2>Почему это записано, а не выброшено</h2>
    <p>Каждое из этих ограничений — про железо, а не про нехватку времени. Их не получится обойти
    усердием: 512 МБ не станет больше, а интерактивный жест закрытия не появится в iOS 6. Список
    существует, чтобы никто не начал реализовывать функцию, которая упрётся в стену на середине,
    и чтобы при выборе дизайна было видно, какой вариант честно выполним, а какой — нет.</p>
  </section>
</div>
'''

if __name__ == '__main__':
    main()
