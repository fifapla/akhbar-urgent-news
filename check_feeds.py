# فحص روابط المصادر: شغّله على جهازك:  python check_feeds.py
import re, urllib.request, concurrent.futures as cf
src = open('lib/main.dart', encoding='utf-8').read()
AJ = 'aljazeerarss/a7c186be-1baa-4bd4-9d80-a84db769f779/73d0e1b4-532f-45ef-b135-bfdff8b8cab9'
feeds = re.findall(r"'(\w+)': FeedDef\('([^']+)', \[(.*?)\]", src, re.S)
def test(u):
    try:
        r = urllib.request.urlopen(urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0'}), timeout=12)
        b = r.read(200000).decode('utf-8', 'ignore')
        return r.status == 200 and ('<item' in b or '<entry' in b)
    except Exception:
        return False
def run(f):
    id_, name, urls = f
    us = [u.replace('$_aj', AJ) for u in re.findall(r"'(http[^']+)'", urls)]
    return id_, name, [(u, test(u)) for u in us]
with cf.ThreadPoolExecutor(12) as ex:
    for id_, name, res in ex.map(run, feeds):
        ok = any(r for _, r in res)
        print(('OK   ' if ok else 'FAIL ') + f'{name} ({id_})')
        if not ok:
            for u, _ in res: print('       ', u)
