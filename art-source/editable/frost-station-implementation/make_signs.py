from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root=Path(__file__).resolve().parents[3]
out=root/'game/previews/frost_station/signs'
out.mkdir(parents=True,exist_ok=True)
font='C:/Windows/Fonts/msyh.ttc'
panels={
'ship':('归航号','维护 / 收藏 / 安装能源'),
'main':('主科研楼','大厅 · 综合实验室 · 二层办公室'),
'museum':('标本保存与隔离馆','未完成的骨架拼装 / 生物介绍'),
'living':('生活医疗楼','宿舍 · 食堂 · 医务'),
'power':('动力与生命保障站','旁路复位 · 供暖 · 慢充补氧'),
'garage':('机修车库','运输车 · 工具与零件'),
'warehouse':('物资仓库','开放库房 / 冰封库房'),
'mission':('能源保险柜在主楼二层','寻找首席留下的钥匙去向线索'),
'layout':('← 楼梯与档案    综合实验室 →','二层：首席办公室 / 观察廊'),
'archives':('档案与设备','开放研究资料 / 器材与备件'),
'safe':('备用能源','钥匙由深入遗迹的首席保管'),
'suction':('手持吸推器','左键吸住小物件 / 右键推出 / 可带走'),
'biology':('骨架观察','长节骨脊与肋骨共同承重；与遗迹的关系仍待研究'),
'living_info':('生活物资','薯片：拿起后使用可吃 / 纪念杯：可带回飞船收藏'),
'power_info':('站区旁路','复位后部分院灯亮起、供暖运行，本地维护台恢复'),
'warehouse_info':('冰封库房','用便携热风机融开表层冰 / 开放库房也有补给'),
'cart':('科考运输车','E上车 / WASD行驶 / E下车 / 车尾E装卸物件'),
}
for key,(title,sub) in panels.items():
    im=Image.new('RGB',(1024,320),'#244653');d=ImageDraw.Draw(im)
    d.rounded_rectangle((12,12,1012,308),18,outline='#79c6ce',width=5)
    d.rectangle((35,40,47,280),fill='#d6b77e')
    for s,y,maxsize in [(title,60,60),(sub,170,35)]:
        size=maxsize
        while d.textlength(s,font=ImageFont.truetype(font,size))>915:size-=1
        d.text((70,y),s,font=ImageFont.truetype(font,size),fill='#eef5e9')
    im.save(out/(key+'.png'))
for key,title,col in [('suction','吸推器','#7bbec8'),('chips','薯片','#d1a65f'),('keepsake','纪念杯','#9bc6be'),('crate','样本箱','#bfae84')]:
    im=Image.new('RGBA',(180,180),(0,0,0,0));d=ImageDraw.Draw(im)
    d.rounded_rectangle((15,18,165,150),25,fill=col,outline='#e2ecdc',width=4)
    d.text((90,65),title,font=ImageFont.truetype(font,34),anchor='mm',fill='#203f4b')
    im.save(out/('icon_'+key+'.png'))
print('Generated',len(panels)+4,'physical sign and item icons')
