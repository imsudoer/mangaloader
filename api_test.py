import asyncio
import aiohttp
import json

HEADERS_API = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:154.0) Gecko/20100101 Firefox/154.0",
    "Accept": "*/*",
    "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
    "Site-Id": "1",
    "Content-Type": "application/json",
    "Client-Time-Zone": "Europe/Moscow",
    "Origin": "https://mangalib.me",
    "Referer": "https://mangalib.me/",
    "Sec-Fetch-Dest": "empty",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Site": "cross-site",
}

async def main():
    async with aiohttp.ClientSession(headers=HEADERS_API) as session:
        # 1. Search
        print("--- SEARCH ---")
        url = "https://api.cdnlibs.org/api/manga?fields[]=rate_avg&fields[]=rate&fields[]=releaseDate&q=berserk&site_id[]=1"
        async with session.get(url) as resp:
            text = await resp.text()
            try:
                data = json.loads(text)
                print(f"Status: {resp.status}")
                if 'data' in data and len(data['data']) > 0:
                    first = data['data'][0]
                    print(json.dumps(first, indent=2, ensure_ascii=False))
                    slug_url = first.get('slug_url')
                else:
                    print(f"No data. Raw response: {text[:200]}")
                    return
            except Exception as e:
                print(f"Parse error: {e}. Raw: {text[:200]}")
                return

        # 2. Details
        print(f"\n--- DETAILS FOR {slug_url} ---")
        url_det = f"https://api.cdnlibs.org/api/manga/{slug_url}?fields[]=summary&fields[]=genres&fields[]=tags&fields[]=authors&fields[]=artists&fields[]=views&fields[]=releaseDate&fields[]=rate_avg&fields[]=rate&fields[]=chap_count&fields[]=status_id&fields[]=format&fields[]=publisher&fields[]=eng_name&fields[]=otherNames&fields[]=background"
        async with session.get(url_det) as resp:
            text = await resp.text()
            data = json.loads(text)
            if 'data' in data:
                d = data['data']
                print(f"Cover default: {d.get('cover', {}).get('default')}")
                print(f"Chapters count: {d.get('items_count', {}).get('uploaded')}")
            else:
                print(f"No details data. Raw: {text[:200]}")

        # 3. Chapters
        print(f"\n--- CHAPTERS FOR {slug_url} ---")
        url_ch = f"https://api.cdnlibs.org/api/manga/{slug_url}/chapters"
        async with session.get(url_ch) as resp:
            text = await resp.text()
            data = json.loads(text)
            if 'data' in data and len(data['data']) > 0:
                print(json.dumps(data['data'][0], indent=2, ensure_ascii=False))
            else:
                print(f"No chapters. Raw: {text[:200]}")

if __name__ == '__main__':
    asyncio.run(main())
