"""Adds the content key `k` to every question of assets/data/bank.json.

k = sha256(casefold(collapse-whitespace(question text))) -- the same function the backend uses (`qkey` in
backend/app/routers/admin_questions.py), so bookmarks/answers saved against the bundled bank still match
questions served by the server. Run after editing the bank:  python tool/add_keys.py assets/data/bank.json
"""
import hashlib, json, sys

def qkey(text: str) -> str:
    return hashlib.sha256(" ".join(text.split()).casefold().encode()).hexdigest()

path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for u in data["units"]:
    for q in u["qs"]:
        q["k"] = qkey(q["q"])
json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print("ok")
