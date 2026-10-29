"""Locally force-align the user-corrected lyrics to the supplied recordings.

The output is an occurrence timeline. Repeated lyric rows are intentionally
kept as separate occurrences; the HDL generator later deduplicates their
glyph rows while retaining every occurrence's real start time.
"""
from pathlib import Path
import json, os, re, subprocess, sys

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tmp/lyrics_asr_20261001"
sys.path.insert(0, str(CACHE / "deps"))
os.environ["HF_HUB_DISABLE_XET"] = "1"
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
from faster_whisper import WhisperModel
from faster_whisper.tokenizer import Tokenizer
from faster_whisper.audio import pad_or_trim
import numpy as np

FFMPEG = r"C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe"

SONG2 = r"C:/Users/28492/Downloads/M500000KkqnP00XOVk.mp3"
SONG3 = r"C:/Users/28492/Desktop/车载图片/我落泪情绪零碎 - 周杰伦.mp3"
SONG4 = r"C:/Users/28492/Desktop/车载图片/周杰伦 - 搁浅.mp3"
SONG5 = r"C:/Users/28492/Desktop/车载图片/272/周杰伦 - 枫.mp3"

def no_space(s):
    return re.sub(r"\s+", "", s)

def align_file(source, blocks, song_id, model, tokenizer):
    raw = subprocess.run([FFMPEG, "-v", "error", "-nostdin", "-i", source,
                          "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000",
                          "-f", "f32le", "pipe:1"], check=True,
                         stdout=subprocess.PIPE).stdout
    audio = np.frombuffer(raw, dtype="<f4")
    result = []
    for bi, (start, stop, lines) in enumerate(blocks):
        assert stop - start <= 30.0, (song_id, bi, stop-start)
        features = model.feature_extractor(audio[round(start*16000):round(stop*16000)])
        words = model.find_alignment(tokenizer, [tokenizer.encode(" ".join(lines)),],
                                     model.encode(pad_or_trim(features)),
                                     min(features.shape[-1], 3000))[0]
        chars = []
        for w in words:
            text = no_space(w["word"])
            if not text:
                continue
            a = start + float(w["start"])
            b = start + float(w["end"])
            for i, ch in enumerate(text):
                chars.append((ch, a + (b-a)*i/len(text),
                              a + (b-a)*(i+1)/len(text)))
        target = no_space("".join(lines))
        actual = "".join(ch for ch, _, _ in chars)
        if actual != target:
            raise RuntimeError(f"song{song_id} block {bi} alignment mismatch: {actual!r} != {target!r}")
        off = 0
        for line in lines:
            count = len(no_space(line))
            span = chars[off:off+count]
            start_cs = round(span[0][1] * 100)
            end_cs = round(span[-1][2] * 100)
            result.append({"start_cs": start_cs, "end_cs": end_cs, "text": line})
            off += count
        print(f"song{song_id} block {bi+1}/{len(blocks)}: {lines[0]}", flush=True)
    result.sort(key=lambda x: (x["start_cs"], x["end_cs"]))
    for i in range(1, len(result)):
        if result[i]["start_cs"] <= result[i-1]["start_cs"]:
            result[i]["start_cs"] = result[i-1]["start_cs"] + 1
    return result

COMBINE = {
    2: [("潺潺的流走", "命运好幽默"), ("回忆如困兽 寂寞太久", "而渐渐温柔"),
        ("放开了拳头", "反而更自由"), ("我们在告别的演唱会", "说好不再见"),
        ("长镜头越拉越远", "越来越远")],
    3: [("感性的句子都枯萎", "凋谢"), ("我不落泪", "忍住感觉"),
        ("冷的咖啡", "我清醒着一再续杯"), ("门外的蔷薇", "带刺伤人的很直接")],
}

def compact(rows, pairs):
    """Combine adjacent display phrases while preserving the first onset."""
    out = []
    i = 0
    pair_map = {a: b for a, b in pairs}
    while i < len(rows):
        if i + 1 < len(rows) and pair_map.get(rows[i]["text"]) == rows[i+1]["text"]:
            out.append({"start_cs": rows[i]["start_cs"],
                        "end_cs": rows[i+1]["end_cs"],
                        "text": rows[i]["text"] + " " + rows[i+1]["text"]})
            i += 2
        else:
            out.append(rows[i]); i += 1
    return out

S2 = [
    (29.8, 38.0, ["时光是琥珀 泪一滴滴被反锁", "情书再不朽 也磨成沙漏"]),
    (38.5, 59.5, ["青春的上游 白云飞走", "苍狗与海鸥 闪过的年头", "潺潺的流走", "命运好幽默", "让爱的人都沉默"]),
    (59.4, 79.5, ["一整个宇宙换一颗红豆", "回忆如困兽 寂寞太久", "而渐渐温柔", "放开了拳头", "反而更自由"]),
    (80.3, 96.0, ["慢动作缱绻胶卷", "重播默片定格一瞬间", "我们在告别的演唱会", "说好不再见"]),
    (93.7, 109.0, ["你写给我 我的第一首歌", "你和我十指紧扣 默写前奏", "可是那然后呢"]),
    (108.1, 125.0, ["还好我有我这一首情歌", "轻轻的轻轻哼着", "哭着笑着我的天长地久"]),
    (139.5, 164.8, ["命运好幽默", "让爱的人都沉默", "一整个宇宙换一颗红豆", "回忆如困兽 寂寞太久", "而渐渐温柔", "放开了拳头", "反而更自由"]),
    (167.7, 183.5, ["长镜头越拉越远", "越来越远", "事隔好几年", "我们在怀念的演唱会", "礼貌地吻别"]),
    (182.9, 198.0, ["你写给我 我的第一首歌", "你和我十指紧扣 默写前奏", "可是那然后呢"]),
    (196.9, 213.5, ["还好我有我这一首情歌", "轻轻的轻轻哼着", "哭着笑着我的天长地久"]),
    (213.8, 232.5, ["陪我唱歌 清唱你的情歌", "舍不得短短副歌", "心还热着 也该告一段落"]),
    (227.9, 244.5, ["还好我有我下一首情歌", "生命宛如静静的相拥的河", "永远天长地久"]),
]

S3 = [
    (15.3, 30.0, ["地上断了翅的蝶 雾散之后的满月", "原来爱跟心碎 都可以很细节"]),
    (29.5, 46.5, ["听夜风绕过几条街", "秋天瘦了满地的落叶", "于是又一整夜", "感性的句子都枯萎凋谢"]),
    (43.8, 73.0, ["我不想再写", "随手撕下这一页", "原来诗跟离别", "可以没有结尾", "憔悴后悔等等这些", "于是我把诗折叠", "邮寄出感觉", "夹一束白玫瑰", "你将爱退回"]),
    (71.5, 93.0, ["我不落泪", "忍住感觉", "分手在起风这个季节", "哭久了会累"]),
    (89.8, 102.0, ["也只是别人的以为", "冷的咖啡", "我清醒着一再续杯"]),
    (100.8, 130.0, ["我落泪 情绪零碎", "你的世界 一幕幕纷飞", "门外的蔷薇", "带刺伤人的很直接", "过去被翻阅", "结局满天的风雪"]),
    (142.3, 170.5, ["我不想再写", "随手撕下这一页", "原来诗跟离别", "可以没有结尾", "憔悴后悔等等这些", "于是我把诗折叠", "邮寄出感觉", "夹一束白玫瑰", "你将爱退回"]),
    (172.0, 187.5, ["我不落泪", "忍住感觉", "分手在起风这个季节", "哭久了会累"]),
    (189.8, 202.0, ["也只是别人的以为", "冷的咖啡", "我清醒着一再续杯"]),
    (200.8, 230.0, ["我落泪 情绪零碎", "你的世界 一幕幕纷飞", "门外的蔷薇", "带刺伤人的很直接", "过去被翻阅", "结局满天的风雪"]),
]

S4 = [
    (16.5, 45.0, ["久未放晴的天空", "依旧留着你的笑容", "哭过 却无法掩埋歉疚", "风筝在阴天搁浅", "想念还在等待救援"]),
    (39.0, 53.5, ["我拉着线 复习你给的温柔", "曝晒在一旁的寂寞", "笑我给不起承诺"]),
    (53.2, 73.0, ["怎么会怎么会", "你竟原谅了我", "我只能永远读着对白", "读着我给你的伤害"]),
    (68.0, 91.0, ["我原谅不了我", "就请你当作我已不在", "我睁开双眼 看着空白", "忘记你对我的期待", "读完了依赖 我很快就离开"]),
    (112.5, 136.0, ["久未放晴的天空", "依旧留着你的笑容", "哭过 却无法掩埋歉疚", "风筝在阴天搁浅", "想念还在等待救援"]),
    (135.0, 143.5, ["我拉着线 复习你给的温柔"]),
    (143.5, 157.5, ["曝晒在一旁的寂寞", "笑我给不起承诺", "怎么会怎么会", "你竟原谅了我"]),
    (156.5, 166.8, ["我只能永远读着对白"]),
    (162.0, 187.8, ["读着我给你的伤害", "我原谅不了我", "就请你当作我已不在", "我睁开双眼 看着空白", "忘记你对我的期待", "读完了依赖 我很快就"]),
    (188.0, 216.0, ["我只能永远读着对白", "读着我给你的伤害", "我原谅不了我", "就请你当作我已不在", "我睁开双眼 看着空白", "忘记你对我的期待"]),
    (214.0, 221.5, ["读完了依赖 我很快就离开"]),
]

S5 = [
    (17.5, 44.5, ["乌云在我们心里搁下一块阴影", "我聆听沉寂已久的心情", "清晰透明 就像美丽的风景", "总在回忆里才看得清"]),
    (46.0, 72.5, ["被伤透的心能不能够继续爱我", "我用力牵起没温度的双手", "过往温柔 已经被时间上锁", "只剩挥散不去的难过"]),
    (74.5, 98.0, ["缓缓飘落的枫叶像思念", "我点燃烛火温暖岁末的秋天", "极光掠夺天边", "北风掠过想你的容颜", "我把爱烧成了落叶"]),
    (98.5, 103.5, ["却换不回熟悉的那张脸"]),
    (102.5, 125.0, ["缓缓飘落的枫叶像思念", "为何挽回要赶在冬天来之前", "爱你穿越时间", "两行来自秋末的眼泪"]),
    (123.0, 133.5, ["让爱渗透了地面", "我要的只是你在我身边"]),
    (146.5, 173.5, ["被伤透的心能不能够继续爱我", "我用力牵起没温度的双手", "过往温柔 已经被时间上锁", "只剩挥散不去的难过"]),
    (173.8, 201.5, ["在山腰间飘逸的红雨", "随着北风凋零", "我轻轻摇曳风铃", "想 唤醒被遗弃的爱情", "雪花已铺满了地", "深怕窗外枫叶已结成冰"]),
    (202.8, 228.5, ["缓缓飘落的枫叶像思念", "我点燃烛火温暖岁末的秋天", "极光掠夺天边", "北风掠过想你的容颜", "我把爱烧成了落叶", "却换不回熟悉的那张脸"]),
    (231.3, 246.0, ["缓缓飘落的枫叶像思念", "为何挽回要赶在冬天来之前", "爱你穿越时间"]),
    (244.0, 267.0, ["两行来自秋末的眼泪", "让爱渗透了地面", "我要的只是你在我身边"]),
]

if __name__ == "__main__":
    model = WhisperModel("small", device="cpu", compute_type="int8", cpu_threads=6,
                         download_root=str(CACHE / "models"), local_files_only=True)
    tokenizer = Tokenizer(model.hf_tokenizer, True, task="transcribe", language="zh")
    songs = {2: (SONG2, S2), 3: (SONG3, S3), 4: (SONG4, S4), 5: (SONG5, S5)}
    out = {}
    for sid, (src, blocks) in songs.items():
        rows = align_file(src, blocks, sid, model, tokenizer)
        out[str(sid)] = compact(rows, COMBINE.get(sid, []))
    dest = ROOT / "tmp/corrected_song_lines_20261015.json"
    dest.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(dest)
