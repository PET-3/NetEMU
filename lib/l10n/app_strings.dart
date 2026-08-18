/// 简易中英文
class S {
  final bool en;
  // ignore: unnecessary_getters_setters
  bool get enFlag => en;
  const S(this.en);
  bool get isEn => en;
  static S of(bool en) => S(en);

  String get appName => 'NetEmu';
  String get home => en ? 'Home' : '首页';
  String get test => en ? 'Test' : '测试';
  String get profiles => en ? 'Profiles' : '配置';
  String get settings => en ? 'Settings' : '设置';
  String get running => en ? 'Running' : '运行中';
  String get stopped => en ? 'Stopped' : '已停止';
  String get start => en ? 'Start' : '开始';
  String get pause => en ? 'Pause' : '暂停';
  String get selectTest => en ? 'Test' : '测试';
  String get selectProfile => en ? 'Profile' : '选择配置';
  String get controlFloat => en ? 'Control float' : '控制浮窗';
  String get infoFloat => en ? 'Info float' : '信息浮窗';
  String get persistentNotif => en ? 'Persistent notification' : '常驻通知';
  String get hideRecents => en ? 'Hide from recents' : '最近任务中隐藏';
  String get params => en ? 'Parameters' : '参数';
  String get traffic => en ? 'Traffic' : '流量';
  String get upload => en ? 'Upload' : '上传';
  String get download => en ? 'Download' : '下载';
  String get randomLoss => en ? 'Random loss' : '随机丢包';
  String get continuousLoss => en ? 'Burst loss' : '连续丢包';
  String get backend => en ? 'Backend (global lock)' : '后端（全局锁定）';
  String get interfaces => en ? 'Interfaces' : '接口';
  String get logs => en ? 'Logs' : '日志';
  String get clear => en ? 'Clear' : '清除';
  String get backup => en ? 'Backup' : '备份';
  String get export => en ? 'Export' : '导出';
  String get import_ => en ? 'Import' : '导入';
  String get language => en ? 'Language' : '语言';
  String get chinese => en ? 'Chinese' : '中文';
  String get english => 'English';
  String get uiStyle => en ? 'UI style' : '界面风格';
  String get styleMaterial => en
      ? 'Material You (Image Toolbox style)'
      : 'Material You（Image Toolbox 风）';
  String get styleSalt => en
      ? 'Salt compact (SaltUI inspired)'
      : 'Salt 紧凑（SaltUI 启发）';
  String get about => en ? 'About' : '关于应用';
  String get project => en ? 'Project' : '项目地址';
  String get thanks => en ? 'Thanks' : '感谢参考';
  String get contact => en ? 'Contact' : '作者联系方式';
  String get save => en ? 'Save' : '保存';
  String get create => en ? 'Create' : '新建';
  String get edit => en ? 'Edit' : '修改';
  String get delete => en ? 'Delete' : '删除';
  String get pickProfileFirst =>
      en ? 'Select Test or a profile first' : '请先选择测试或配置';
}
