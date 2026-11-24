# 共振星语音日志脚本

这些日志用于玩家在探索过程中发现，逐步理解共振星的背景。

---

## 日志 1：设施介绍
**触发条件：** 玩家第一次靠近热阀链（热阀距离 < 15 米）
**角色：** 工程主管（已故）
**音色指引：** 沙哑、沧桑、略带疲惫的低沉男性声音
**背景音：** 微弱的机器嗡鸣 + 电子底纹

**文本：**
```
这是...共振能源站的核心区域。
[停顿 0.5 秒]
三条热阀链连接了地下的地热循环系统。
当年我们建立这个设施，就是为了给舰队源源不断地提供能量。
[停顿 1 秒]
一千艘战舰，都靠这儿活着。
现在...只有冻结的反应堆，和这些被遗忘的机械。
[停顿 0.5 秒]
也许...有朝一日，会有人来重启它。
```

**Duration:** ~18 秒
**AI 任务：**
- 中文 TTS（ElevenLabs 中文模型或 Azure TTS）
- 音色：male-gravelly-chinese (沙哑、中年、疲倦)
- 速度：0.9x (略显拖沓)
- 间隔音效：每个停顿加入"机器低频声" (-20dB)

---

## 日志 2：事故背景
**触发条件：** 玩家第一次靠近反应堆塔（反应堆距离 < 20 米）
**角色：** 年轻的技术员
**音色指引：** 焦急、年轻、中等音量的男性声音
**背景音：** 警报声 + 急促的机械音（失控状态的混乱感）

**文本：**
```
[背景警报声持续]
所有人听着！所有人听着！
指挥官刚下达了冻结命令。
[停顿 0.3 秒]
核心能量读数超过安全值 340%，温度在上升。
如果不立即隔离，整个设施会...会...
[声音变得急促]
我们把备用能源核心搬到了深层接收座。
已经封存，已经锁定。
[停顿 0.5 秒]
希望有朝一日，有人能来重启它。
也许...也许那才是真正的救赎。
```

**Duration:** ~21 秒
**AI 任务：**
- 中文 TTS
- 音色：male-young-urgent-chinese
- 速度：1.1x (紧张感)
- 情感参数：anxiety, urgency 最大化
- 背景混音：警报音 -15dB，机械噪声 -18dB

---

## 日志 3：最后希望（核心拿取时）
**触发条件：** 玩家拿起能源核心瞬间
**角色：** 工程主管（第一个声音，更虚弱）
**音色指引：** 非常沙哑、疲惫、接近生命终点的声音
**背景音：** 极其微弱的机器音 + 余音（像是录音的最后片段）

**文本：**
```
[咳嗽声]
如果...如果你听到这个录音，说明你已经找到了。
[停顿 1 秒，呼吸声]
你拿起了那个核心。
[停顿，虚弱的笑声]
我已经...等不到这一天了。
但...也许你能做到。
[停顿 1.5 秒]
出去吧。带着它离开这个地方。
找到能利用它的人。
[最后停顿，声音渐弱]
这是...我们最后的...希望。
```

**Duration:** ~17 秒
**AI 任务：**
- 中文 TTS
- 音色：male-old-gravelly-dying-chinese (非常沙哑，生命垂危)
- 速度：0.85x (非常缓慢)
- 情感参数：resigned, hopeful, weak 混合
- 音量：自动渐弱（淡出）
- 添加效果：轻微的回声（录音老化感）、咳嗽音 x2、呼吸声间隔

---

## 日志对应的 Godot 事件钩子

```gdscript
class ResonanceVoiceLogManager:
    # 日志触发条件
    var log_triggered = {
        "intro": false,
        "accident": false,
        "core_pickup": false
    }
    
    func check_voice_log_triggers(player_pos: Vector3):
        # 日志 1：靠近热阀
        if not log_triggered["intro"]:
            var nearest_valve = find_nearest_heat_valve(player_pos)
            if nearest_valve and nearest_valve.distance_to(player_pos) < 15.0:
                play_voice_log("intro", "res://assets/resonance/audio/log_intro.ogg")
                log_triggered["intro"] = true
        
        # 日志 2：靠近反应堆
        if not log_triggered["accident"]:
            if player_pos.distance_to(REACTOR_POSITION) < 20.0:
                play_voice_log("accident", "res://assets/resonance/audio/log_accident.ogg")
                log_triggered["accident"] = true
    
    func on_core_pickup():
        # 日志 3：拿起核心
        if not log_triggered["core_pickup"]:
            play_voice_log("core", "res://assets/resonance/audio/log_core.ogg")
            log_triggered["core_pickup"] = true
    
    func play_voice_log(log_id: String, audio_path: String):
        # 清除HUD干扰
        hud.hide_temporary_ui()
        
        # 播放日志
        voice_player.stream = load(audio_path)
        voice_player.play()
        
        # 字幕同步（可选）
        if log_id == "intro":
            show_subtitle("这是...共振能源站的核心区域。", 3.0)
        elif log_id == "accident":
            show_subtitle("指挥官刚下达了冻结命令！", 2.5)
        elif log_id == "core":
            show_subtitle("出去吧...带着它离开...", 3.5)
```

---

## 文本翻译版本（如需英文）

### Log 1: Facility Introduction
```
This is... the heart of Resonance Energy Station.
[pause]
Three heat valve chains connect to the geothermal circulation system below.
When we built this facility, it was to provide endless power to the fleet.
[pause]
A thousand ships lived because of this.
Now... only the frozen reactor remains, and these forgotten machines.
[pause]
Perhaps... someday, someone will come to restart it.
```

### Log 2: Accident Background
```
Listen to me! Everyone listen!
The commander just issued the freeze order.
[pause]
Core energy readings exceed 340% of safety threshold. Temperature is rising.
If we don't isolate immediately, the entire facility will... will...
[urgent]
We've moved the backup energy core to the deep receiver chamber.
Already sealed. Already locked.
[pause]
I hope that someday, someone can come and restart it.
Maybe... maybe that's true redemption.
```

### Log 3: Last Hope
```
[cough]
If... if you're hearing this, you've found it.
[pause, breathing]
You've taken that core.
[pause, weak laugh]
I won't live to see this day. But... maybe you can make it.
[pause]
Get out. Take it away from this place.
Find someone who can use it.
[final pause, voice fades]
This is... our last... hope.
```

---

## 音频生成步骤

### 方案 A：ElevenLabs API（推荐 - 质量最高）

```python
import requests
import json

ELEVENLABS_API_KEY = "your_api_key_here"
VOICE_ID_GRAVELLY = "pNInz6obpgDQGcFmaJgB"  # Adam (gravelly male)
VOICE_ID_URGENT = "nPczCjzI2devNBz1zQrb"   # Callum (young urgent)

logs = [
    {
        "id": "intro",
        "text": "这是...共振能源站的核心区域...",
        "voice_id": VOICE_ID_GRAVELLY,
        "stability": 0.4,  # 不稳定 = 更疲倦
        "similarity": 0.7,
    },
    {
        "id": "accident",
        "text": "所有人听着！",
        "voice_id": VOICE_ID_URGENT,
        "stability": 0.6,
        "similarity": 0.8,
    },
    {
        "id": "core",
        "text": "这是...我们最后的...希望。",
        "voice_id": VOICE_ID_GRAVELLY,
        "stability": 0.3,  # 极不稳定 = 极度虚弱
        "similarity": 0.65,
    },
]

for log in logs:
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{log['voice_id']}"
    headers = {"xi-api-key": ELEVENLABS_API_KEY}
    payload = {
        "text": log["text"],
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {
            "stability": log["stability"],
            "similarity_boost": log["similarity"],
        }
    }
    
    response = requests.post(url, json=payload, headers=headers)
    with open(f"resonance_log_{log['id']}.mp3", "wb") as f:
        f.write(response.content)
    print(f"Generated: resonance_log_{log['id']}.mp3")
```

### 方案 B：Azure Text-to-Speech（免费额度）

```python
import azure.cognitiveservices.speech as speechsdk

speech_config = speechsdk.SpeechConfig(
    subscription="your_azure_key",
    region="your_region"
)

# 中文女性声音（适合年轻技术员）
speech_config.speech_synthesis_voice_name = "zh-CN-YunyeNeural"

synthesizer = speechsdk.SpeechSynthesizer(
    speech_config=speech_config,
    audio_config=speechsdk.audio.AudioOutputConfig(filename="output.wav")
)

text = "所有人听着！指挥官刚下达了冻结命令。"
result = synthesizer.speak_text_async(text).get()
```

### 方案 C：Google Cloud TTS

```python
from google.cloud import texttospeech

client = texttospeech.TextToSpeechClient()

synthesis_input = texttospeech.SynthesisInput(text="这是共振能源站的核心区域")

voice = texttospeech.VoiceSelectionParams(
    language_code="zh-CN",
    name="zh-CN-Neural2-A",  # 男性声音
)

audio_config = texttospeech.AudioConfig(
    audio_encoding=texttospeech.AudioEncoding.MP3,
    speaking_rate=0.9,  # 0.9x 速度（略显拖沓）
)

response = client.synthesize_speech(
    input=synthesis_input, voice=voice, audio_config=audio_config
)

with open("resonance_log_intro.mp3", "wb") as out:
    out.write(response.audio_content)
```

---

## 混音与后期处理

用 Audacity 或 FFmpeg 完成：

```bash
# 1. 导入日志 MP3
# 2. 添加背景音效轨道
#   - 日志 1：机器嗡鸣 (ambient_industrial.mp3)
#   - 日志 2：警报声 (alarm_warning.mp3)
#   - 日志 3：极微弱的回声

# 3. 音量平衡
#   - 日志主音：-6dB
#   - 背景音效：-18dB 到 -22dB

# 4. 导出为 OGG（Godot 优化格式）
ffmpeg -i resonance_log_intro_mixed.wav \
       -codec:a libvorbis -q:a 8 \
       resonance_log_intro.ogg
```

---

## 验收标准

✅ **文本质量：**
- [ ] 日志 1 能传达"这是重要设施"的信息
- [ ] 日志 2 能传达"事故很严重"的紧张感
- [ ] 日志 3 能传达"你有责任"的使命感

✅ **音频质量：**
- [ ] 日志 1 声音沙哑、疲倦
- [ ] 日志 2 声音急促、紧张（不是刺耳）
- [ ] 日志 3 声音虚弱、即将消逝

✅ **集成效果：**
- [ ] 玩家听到日志后明白"为什么来这儿"
- [ ] 玩家听到日志后明白"在做什么"
- [ ] 玩家听到日志后感觉"这很重要"

---

## 立即行动

**今天：**
1. 选择 TTS 方案（推荐 ElevenLabs，如果预算紧用 Azure/Google）
2. 生成 3 个 MP3 文件
3. 混音处理（加背景音效）
4. 导出为 OGG

**明天：**
5. 在 Godot 实现 `ResonanceVoiceLogManager`
6. 测试触发条件

完整的叙事深化就开始了。要我帮你写生成脚本吗？
