/// 各参数 ⓘ 文案（集中管理，界面不堆说明字）
class ParamInfos {
  static const delay =
      '单向附加延迟（毫秒）。0 表示不额外延迟。VPN 与 Root/tc 均可生效。';
  static const jitter =
      '在延迟基础上的随机波动（±抖动）。用于模拟不稳定链路。';
  static const bandwidth =
      '令牌桶限速。0 = 不限速。单位 Kbps。Root 模式通过 tc 限速。';
  static const loss =
      '每个包独立按该百分比随机丢弃。';
  static const contMode =
      '包数：连续放行 N 个包后丢弃 M 个。\n时间：连续放行 N 毫秒后丢弃 M 毫秒。';
  static const contPass = '连续丢包状态机中的「放行」阶段长度（包数或毫秒）。';
  static const contDrop = '连续丢包状态机中的「丢弃」阶段长度（包数或毫秒）。';
  static const protocol =
      '仅对 VPN 用户态路径生效：可只模拟 TCP、只模拟 UDP，或全部。';
  static const floatControl =
      '小号可拖动控制条，可最小化。需「显示在其他应用上层」权限。';
  static const floatInfo =
      '显示模拟路径速度与丢包计数（非系统全网测速）。';
  static const notification =
      '前台服务常驻通知，便于从通知栏查看状态并快速操作。';
  static const hideRecent =
      '从系统最近任务列表中隐藏本应用卡片，降低被误划掉的概率（部分系统有效）。';
  static const backend =
      '全局锁定一种后端，启动后按此执行，不再自动切换。\n'
      'VPN：无 Root。Root：tc。ADB：仅导出命令。\n'
      'Shizuku：需集成官方库后才会出现在授权列表（当前为检测级）。';
  static const profile =
      '选中已有配置后，首页按该配置只读运行。\n'
      '选择「测试」则使用测试页可调参数，并可保存为新配置。';
  static const stats =
      '统计为模拟路径上的字节/包/丢包，与系统状态栏全网测速口径不同。';
  static const testMode =
      '独立可调参数页。在首页点「测试」进入；保存后可写入配置管理。';
}
