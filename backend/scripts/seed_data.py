import requests
import json
import os
import shutil
import uuid

# Base URL
BASE_URL = "http://127.0.0.1:8000"

# Sample images (using placeholders for now, in a real scenario we'd download them)
# For this script to work robustly without external dependencies, we'll generate simple colored images locally.
from PIL import Image, ImageDraw, ImageFont

def create_dummy_image(text, color, filename):
    img = Image.new('RGB', (400, 400), color=color)
    d = ImageDraw.Draw(img)
    # Just draw some text
    d.text((50, 180), text, fill=(255, 255, 255))
    path = f"backend/scripts/{filename}"
    img.save(path)
    return path

# Ensure backend/scripts exists
os.makedirs("backend/scripts", exist_ok=True)

# Generate dummy images
images = [
    {"text": "Vintage Camera", "color": "#4E342E", "file": "camera.jpg"},
    {"text": "Old Watch", "color": "#FF6F00", "file": "watch.jpg"},
    {"text": "Letters", "color": "#FBC02D", "file": "letters.jpg"},
    {"text": "Toy Car", "color": "#1565C0", "file": "toy.jpg"},
    {"text": "Ceramic Vase", "color": "#00695C", "file": "vase.jpg"},
]

generated_files = []
try:
    for img in images:
        path = create_dummy_image(img["text"], img["color"], img["file"])
        generated_files.append(path)
except ImportError:
    print("Pillow not installed. Please run 'pip install Pillow' first.")
    exit(1)

# Upload and Create Items
items_data = [
    {
        "title": "祖父的胶片相机",
        "category": "摄影器材",
        "tags": ["传家宝", "胶片", "1980s"],
        "description": "这是祖父年轻时使用过的海鸥牌双反相机，快门的声音依然清脆。虽然现在很少用了，但每次看到它都能想起那个年代的质朴。",
        "mood": "怀旧",
        "img_index": 0
    },
    {
        "title": "旧怀表",
        "category": "钟表",
        "tags": ["金属", "停摆", "精致"],
        "description": "一块不再走动的怀表，指针永远停在了下午三点。表盖上的划痕记录着岁月的流逝。",
        "mood": "忧郁",
        "img_index": 1
    },
    {
        "title": "泛黄的信件",
        "category": "文书",
        "tags": ["纸质", "书信", "情感"],
        "description": "一叠用红线捆扎的信件，纸张已经变脆发黄。字迹虽然有些模糊，但那份真挚的情感依然滚烫。",
        "mood": "温暖",
        "img_index": 2
    },
    {
        "title": "铁皮玩具车",
        "category": "玩具",
        "tags": ["童年", "铁皮", "掉漆"],
        "description": "小时候最喜欢的铁皮小汽车，虽然车轮已经生锈，油漆也剥落了不少，但它是童年最快乐的伙伴。",
        "mood": "宁静",
        "img_index": 3
    },
    {
        "title": "青花瓷瓶",
        "category": "瓷器",
        "tags": ["易碎", "传统", "装饰"],
        "description": "家里摆放多年的花瓶，釉色依然温润。瓶口的细微裂纹是某次搬家时不小心留下的。",
        "mood": "神秘",
        "img_index": 4
    }
]

for item in items_data:
    print(f"Processing: {item['title']}...")
    
    # 1. Upload Image
    img_path = generated_files[item["img_index"]]
    with open(img_path, "rb") as f:
        files = {"file": (os.path.basename(img_path), f, "image/jpeg")}
        resp = requests.post(f"{BASE_URL}/upload/", files=files)
        if resp.status_code != 200:
            print(f"Failed to upload image for {item['title']}: {resp.text}")
            continue
        upload_data = resp.json()
        image_url = upload_data["url"]
    
    # 2. Create Item
    create_payload = {
        "title": item["title"],
        "category": item["category"],
        "tags": item["tags"],
        "description": item["description"],
        "image_paths": [image_url]
    }
    resp = requests.post(f"{BASE_URL}/items/", json=create_payload)
    if resp.status_code != 200:
        print(f"Failed to create item {item['title']}: {resp.text}")
        continue
    
    item_id = resp.json()["id"]
    
    # 3. Update Mood (AI Metadata)
    patch_payload = {
        "ai_metadata": {"mood": item["mood"], "material": "模拟材质", "era_guess": "模拟年代"}
    }
    requests.patch(f"{BASE_URL}/items/{item_id}", json=patch_payload)
    
    print(f"Successfully created: {item['title']} (ID: {item_id})")

print("\nDone! Seed data injected.")

# Cleanup temporary images
# for f in generated_files:
#     os.remove(f)
