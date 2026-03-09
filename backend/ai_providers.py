import os
import json
from typing import Optional, Tuple, List, Dict
import requests

CN_MOODS = ["怀旧", "温暖", "忧郁", "宁静", "神秘"]
CN_CATEGORIES = ["衣物", "电子用品", "家具", "玩具", "纸制品", "生活用品", "私密用品"]

def _gemini_chat(prompt: str) -> Optional[str]:
    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        return None
    model = os.getenv("GEMINI_MODEL", "gemini-1.5-pro")
    url = f"https://generativelanguage.googleapis.com/v1/models/{model}:generateContent?key={api_key}"
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [{"text": prompt}],
            }
        ]
    }
    headers = {"Content-Type": "application/json"}
    try:
        resp = requests.post(url, headers=headers, data=json.dumps(payload), timeout=15)
        if resp.status_code != 200:
            return None
        data = resp.json()
        cands = data.get("candidates") or []
        if not cands:
            return None
        parts = (cands[0].get("content") or {}).get("parts") or []
        if not parts:
            return None
        text = parts[0].get("text")
        return text
    except Exception:
        return None

def _zhipu_chat(prompt: str) -> Optional[str]:
    api_key = os.getenv("ZHIPUAI_API_KEY")
    if not api_key:
        return None
    url = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    payload = {
        "model": os.getenv("ZHIPUAI_MODEL", "glm-4"),
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.7,
    }
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    try:
        resp = requests.post(url, headers=headers, data=json.dumps(payload), timeout=15)
        if resp.status_code != 200:
            return None
        data = resp.json()
        choices = data.get("choices") or []
        if not choices:
            return None
        return choices[0].get("message", {}).get("content")
    except Exception:
        return None

def _dashscope_chat(prompt: str) -> Optional[str]:
    api_key = os.getenv("DASHSCOPE_API_KEY")
    if not api_key:
        return None
    url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
    model = os.getenv("DASHSCOPE_MODEL", "qwen-plus")
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    payload = {"model": model, "input": prompt}
    try:
        resp = requests.post(url, headers=headers, data=json.dumps(payload), timeout=15)
        if resp.status_code != 200:
            return None
        data = resp.json()
        out = data.get("output", {})
        return out.get("text")
    except Exception:
        return None

def _first_available(prompt: str) -> Optional[str]:
    # 优先使用通义 DashScope
    out = _dashscope_chat(prompt)
    if out:
        return out
    # 其次使用智谱 GLM
    out = _zhipu_chat(prompt)
    if out:
        return out
    # 备用：Google Gemini（境外环境）
    out = _gemini_chat(prompt)
    if out:
        return out
    return None

def _extract_mood(text: str) -> Optional[str]:
    for m in CN_MOODS:
        if m in text:
            return m
    return None

def generate_description(item: Dict[str, any], style: Optional[str]) -> Tuple[str, Dict[str, any]]:
    title = item.get("title") or "无名旧物"
    imgs = item.get("image_paths") or []
    prompt = (
        "你是物品档案描述助手。请为用户的旧物生成一段不超过120字的中文描述，兼顾材质与年代感，语气温和。"
        f"物品标题：{title}\n"
        f"图片数量：{len(imgs)}\n"
        f"风格：{style or '通用'}\n"
        "请只返回中文段落，不要返回多余解释。"
    )
    text = _first_available(prompt)
    if not text:
        import random
        mood = random.choice(CN_MOODS)
        materials = ["木质", "金属", "塑料", "织物", "陶瓷"]
        eras = ["80年代", "90年代", "2000年初", "近现代"]
        material = random.choice(materials)
        era = random.choice(eras)
        desc = f"它静静地躺着，透出{mood}的气息。来自{era}的{material}构造，光影下细节迷人。"
        meta = {"mood": mood, "material": material, "era_guess": era}
        return desc, meta
    mood = _extract_mood(text)
    meta = {}
    if mood:
        meta["mood"] = mood
    return text.strip(), meta

def classify_item(item: Dict[str, any]) -> Tuple[str, List[str]]:
    title = item.get("title") or "无名旧物"
    prompt = (
        "你是物品分类助手。请根据标题与已知信息为该物品给出一个中文类别，以及8个中文标签。"
        f"标题：{title}\n"
        "以纯JSON返回：{\"category\":\"类别\",\"tags\":[\"标签1\",...]}，不允许任何其它文本。"
    )
    text = _first_available(prompt)
    if not text:
        import random
        cat = random.choice(CN_CATEGORIES)
        tags = ["年代", "材质", "保存状态", "复古", "记忆", "生活", "细节", "情绪"]
        return cat, tags
    try:
        data = json.loads(text)
        cat = str(data.get("category") or "").strip() or CN_CATEGORIES[0]
        tags = [str(t) for t in (data.get("tags") or [])]
        if not tags:
            tags = ["复古", "生活", "细节"]
        return cat, tags[:12]
    except Exception:
        return CN_CATEGORIES[0], ["复古", "生活", "细节"]
