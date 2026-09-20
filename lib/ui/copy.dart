// 用户可见文案唯一出处 — 成段指引文案集中于此，润色只改这个文件（profile-polish 票）。
// 纪律：不在 widget 里拼句子（整句进来，变量走参数）；不拆词组装（为将来多语言铺路）。
// 短标签（「确定」「账本管理」这类按钮/行标题）不搬家，留在各 widget 原地。
import 'common/format.dart';

// ── 通用 ─────────────────────────────────────

// 信封解析失败时的兜底称呼
const unknownEnvelope = '(已停用信封)';

// 用户卡默认昵称（未设置时显示）
const defaultNickname = '记账的你';

// 用户卡默认签名（未设置时显示）
const defaultSignature = '数据存在本机，无云同步 · 点击可编辑（仅装饰作用）';

// ── 编辑资料（我的页用户卡进入）──────────────

// 页面标题
const editProfileTitle = '编辑资料';

// 头像区提示
const avatarChangeHint = '点头像可更换';
const resetAvatarLabel = '恢复默认头像';

// 表单标签与提示
const nicknameLabel = '昵称';
const nicknameHint = '想被怎么称呼？';
const signatureLabel = '签名';
const signatureHint = '一句话介绍自己（选填）';

// 保存结果 toast
const profileSavedToast = '资料已保存';

// 头像图片读取失败 toast
const avatarPickFailedToast = '图片读取失败，换一张试试？';

// ── 手势教练（DESIGN.md §17）─────────────────

// 教练三步的标题
const coachStep1Title = '第一步 · 分配';
const coachStep2Title = '第二步 · 记一笔支出';
const coachStep3Title = '第三步 · 双击也能记支出';

// 教练第 1 步正文：拖卡分配（信封名由调用处解析后传入）
String coachStep1Body(String envelopeName) =>
    '按住这里的「待规划」区域，拖到任意信封上松手（比如「$envelopeName」），输入金额完成分配。';

// 教练第 2 步正文：拖到边缘记支出
const coachStep2Body = '按住任意信封卡，往下拖到底边提示区域松开手指记录支出。';

// 教练第 3 步正文：双击信封记支出
const coachStep3Body = '不想拖动？在信封卡上快速点两下，也能记录支出。';

// 落点带横幅（首页与教练共用，§4 逐字规格）
const dragEdgeBandLabel = '花花花，买买买';

// 跳过引导按钮（教练与三屏引导共用）
const skipCoachLabel = '跳过引导';

// ── 新账本三屏引导（DESIGN.md §11）───────────

// 第 1 屏：记收入
const onboardIncomeTitle = '先点清手头有多少钱';
const onboardIncomeBody = '记录手头上可以支配的钱，比如把微信、支付宝、银行卡里的钱加一块儿。';
const onboardReopenKeypadLabel = '再记一笔';

// 第 2 屏：挑信封
const onboardPickTitle = '挑几个信封开始';
const onboardPickBody = '可以根据自己的需求，挑几个信封开始，之后随时能改。';

// 第 3 屏：分钱
const onboardAllocateTitle = '先把钱分下去';
const onboardAllocateBody = '不分完也没关系，剩下的会留在待规划里，随时可再分。';
const onboardRemainLabel = '还剩在「待规划」';
const onboardAllocateHint = '点哪一行都能改金额；先不分也行，留着以后再分。';

// 模板信封重名提示（同名可能来自恢复的停用信封，创建被跳过）
String onboardNameConflictToast(String name) => '「$name」已经有了，帮你跳过了';

// ── 数字键盘（DESIGN.md §5）──────────────────

// 键盘标题（按动作语境，信封名由调用处解析）
String keypadAssignTitle(String envelopeName) => '分配到「$envelopeName」';
String keypadUnassignTitle(String envelopeName) => '从「$envelopeName」撤回待规划';
String keypadTransferTitle(String fromName, String toName) =>
    '从「$fromName」转到「$toName」';
const keypadExpenseTitle = '记一笔支出';
const keypadIncomeTitle = '记一笔收入';
const keypadEditAmountTitle = '改金额';

// 键盘副标题（上下文行）。货币符号由调用方传当前账本设置（ADR-0017）
String keypadAssignSubtitle(double toBudget, {required String symbol}) =>
    '待规划还有 $symbol${money(toBudget)} 可分配';
String keypadUnassignSubtitle(double available, {required String symbol}) =>
    '这个信封有 $symbol${money(available)} 可以撤回';
String keypadTransferSubtitle(
  String fromName,
  double available, {
  required String symbol,
}) => '「$fromName」剩余 $symbol${money(available)}';
String keypadExpenseSubtitle(
  String envelopeName,
  double available, {
  required String symbol,
}) => '从「$envelopeName」支出 · 剩余 $symbol${money(available)}';
const keypadIncomeSubtitle = '钱先进「待规划」，之后再分给信封';
String keypadEditAmountSubtitle(
  double amount,
  String description, {
  required String symbol,
}) => '原来是 $symbol${money(amount)} · $description';

// 描述栏占位文案（把兜底结果直接说出来，ADR-0008）
String placeholderAssign(String envelopeName) =>
    '选填 · 不填就记作「待规划 → $envelopeName」';
String placeholderUnassign(String envelopeName) =>
    '选填 · 不填就记作「$envelopeName → 待规划」';
String placeholderTransfer(String fromName, String toName) =>
    '选填 · 不填就记作「$fromName → $toName」';
String placeholderExpense(String envelopeName) => '选填 · 不填就记作「$envelopeName」';
const placeholderIncome = '选填 · 不填就记作「一笔收入」';
String placeholderEditAmount(String currentDescription) =>
    '选填 · 不填就保持「$currentDescription」';

// 计算器无法求值提示
const keypadEvalErrorHint = '这个式子算不出来，再看看？';

// ── 键盘提交流程 toast ───────────────────────

// 撤回（信封 → 待规划）完成
String toastUnassigned(double amount) => '已把 ${money(amount)} 退回待规划';

// 转出（信封 → 信封）完成
String toastTransferredOut(String fromName, double amount) =>
    '已从「$fromName」转出 ${money(amount)}';

// 支出完成但透支（透支合法照记，提示去流水补，不变量①；信封缺失时保留原样不兜底）
String toastExpenseOverspent(String? envelopeName, double overdraftAmount) =>
    '记下了。不过「$envelopeName」透支了 ${money(overdraftAmount)}——去流水里点「去补上」';

// 支出完成（信封缺失时保留原样不兜底）
String toastExpense(String? envelopeName, double amount) =>
    '已从「$envelopeName」支出 ${money(amount)}';

// 收入完成
String toastIncome(double amount) => '收入 ${money(amount)} 已进入待规划';

// 改金额完成
String toastAmountEdited(double amount) => '金额已改为 ${money(amount)}';

// 分配完成（含快捷分配面板共用）
String toastAssigned(double amount, String envelopeName) =>
    '已把 ${money(amount)} 分到「$envelopeName」';

// ── 空状态（DESIGN.md §14）───────────────────

// 首页：还没有信封
const emptyHomeTitle = '还没有信封';
const emptyHomeBody = '先建几个信封，把待规划里的钱分下去';
const emptyHomeCta = '新建第一个信封';

// 流水页：还没有流水 / 被筛空
const emptyTxnsTitle = '还没有流水';
const emptyTxnsBody = '在首页记一笔收入，或拖动信封记支出';
const emptyFilteredTitle = '没有符合条件的流水';
const emptyFilteredBody = '试试调整或清除筛选条件';

// 统计页：无支出 / 无信封
const emptyExpenseTitle = '这个范围里还没有支出';
const emptyEnvelopesForStats = '还没有信封，先去首页建几个吧';

// 信封详情：该信封无流水
const emptyEnvelopeTxns = '还没有这个信封的流水';

// ── 预算周期与结转（ADR-0013/0015）────────────

// 结转铁律共享句（两个确认框共用，语义变更时只改这里）
const _carryoverRulesLine =
    '正结余看信封的结转开关'
    '（关=剩余退回待规划），负缺口无论开关都会带入，待规划原样保留。';

// 切换类型/修改起始日的结转预告（确认框正文）
const carryoverConfirmBody = '将立即按新周期结转：$_carryoverRulesLine';

// 自由周期「结束本期」确认框正文
const closePeriodConfirmBody = '结转后新一期从今天开始：$_carryoverRulesLine';

// 结转开关副标题（新建/编辑信封共用语义：关=剩余退回待规划，ADR-0015）
const carryoverSwitchSubtitle = '关掉则结转时剩余退回待规划';

// ── 交易详情与撤销（DESIGN.md §16）───────────

// 详情页底部规则提示
const txnEditRulesHint = '点金额或描述就能改。改完相关信封的余额会自动重算；不可跨月修改';

// 结转退回详情页提示（ADR-0016：系统行为，替代 txnEditRulesHint 出现）
const refundDetailHint = '这条记录由周期结转自动生成：金额退回待规划、不计收支，不可修改也不可撤销。';

// 改描述对话框占位
const editDescriptionHint = '描述这笔记录';

// 撤销确认框固定尾行
const revertIrreversibleLine = '撤销后这条流水会从列表移除，不能恢复。';

// 停用信封撤销说明（ADR-0012：只删档案不动余额）
String revertArchivedConsequence(String archivedName) =>
    '「$archivedName」已停用：撤销不会改变任何余额，只会把这条档案记录从流水里移除。';

// 撤销致待规划为负的拦截说明（不变量⑦）
const revertWouldGoNegativeBody = '这笔钱已经分出去了，若直接撤销会使待规划变负，请先撤回几笔分配再试。';

// 撤销成功 toast
const toastReverted = '已撤销，余额已重算';

// 撤销后果文案（对比撤销前后关键数字，§16.1；名字可空时保留原样不兜底）。
// 货币符号由调用方传当前账本设置（ADR-0017）
const revertFallbackConsequence = '相关信封的余额会重算。';
String revertExpenseConsequence(
  String name,
  double usedBefore,
  double usedAfter,
  double availableAfter, {
  required String symbol,
}) =>
    '撤销后「$name」的已使用会从 $symbol${money(usedBefore)} '
    '退回 $symbol${money(usedAfter)}，剩余回到 $symbol${money(availableAfter)}。';
String revertIncomeConsequence(
  double toBudgetBefore,
  double toBudgetAfter, {
  required String symbol,
}) =>
    '撤销后待规划会从 $symbol${money(toBudgetBefore)} '
    '回到 $symbol${money(toBudgetAfter)}。';
String revertAssignConsequence(
  String? toName,
  double plannedBefore,
  double plannedAfter,
  double toBudgetAfter, {
  required String symbol,
}) =>
    '撤销后「$toName」的已规划会从 $symbol${money(plannedBefore)} '
    '回到 $symbol${money(plannedAfter)}，待规划回到 $symbol${money(toBudgetAfter)}。';
String revertUnassignConsequence(
  String? fromName,
  double plannedBefore,
  double plannedAfter, {
  required String symbol,
}) =>
    '撤销后「$fromName」的已规划会从 $symbol${money(plannedBefore)} '
    '变为 $symbol${money(plannedAfter)}。';
String revertTransferConsequence(String? fromName, String? toName) =>
    '撤销后「$fromName」与「$toName」的已规划会恢复原状。';

// ── 备份与恢复（DESIGN.md §19）───────────────

// 备份页首说明
const backupIntroBody = '备份包含全部账本（信封、流水、设置）。建议备份后把 .jx 文件再存到网盘或电脑一份。';

// 备份列表为空
const backupEmptyBody = '还没有备份。点上方「立即备份」生成第一份。';

// 「从文件恢复」行的副标签
const restoreFromFileSubLabel = '选择一台设备导出的 .jx 文件';

// 页脚覆盖提示
const restoreCoverHint = '恢复会用所选备份覆盖当前所有数据，操作前请确认备份时间。';

// 覆盖恢复确认框正文（todayCount 算不出时按 0 处理，不阻断恢复）
String restoreCoverConfirmBody(String timeLabel, int todayCount) =>
    '恢复会用 $timeLabel 的备份覆盖当前所有数据'
    '${todayCount > 0 ? '，今天新增的 $todayCount 笔流水会消失' : ''}。';

// 备份内容损坏（库读得出来但校验失败）
const restoreCorruptBody = '这份备份没能读出来，可能已损坏。你的当前数据没有被改动。';

// 文件本身读不出来
const restoreFileCorruptBody = '文件可能已损坏，请换一份备份。你的当前数据没有被改动。';

// 恢复成功 toast
String toastRestored(String timeLabel) => '已恢复 $timeLabel 的备份';

// 导出/备份 toast（备份与 CSV 共用「正在导出…」「已导出到所选位置」）
const toastExporting = '正在导出…';
const toastExportedToPicker = '已导出到所选位置';
String toastExportedToPath(String path) => '已导出到 $path';
String toastBackupFailed(Object error) => '备份失败：$error';
const toastBackupLocalOnly = '已备份到本地（最近保留 5 份）';
String toastBackupLocalExportFailed(Object error) => '已备份到本地；导出到文件失败：$error';
const toastCsvEmpty = '当前账本还没有流水，没什么可导出的';
const toastExportCancelled = '导出已取消';

// ── 自动备份（DESIGN.md §19 · v1.2.x 票 02 · ADR-0018）────

// 开关行副标签
const autoBackupSwitchSubtitle = '数据变动后约 3 秒自动备份';

// 状态行第一行：最近一次结果（失败静默，只反映在这里）
const autoBackupStatusNever = '尚未生成 · 有数据变动时会自动备份';
String autoBackupStatusSuccess(String timeLabel) => '上次自动备份 · $timeLabel';
String autoBackupStatusFailure(String timeLabel) =>
    '上次尝试失败，下次变动时会重试 · $timeLabel';

// 状态行第二行：固定位置。公共目录（Android 下载）卸载重装仍在；
// 沙盒（iOS / 低版本 Android 降级）不承诺卸载可恢复，文案如实说明
const autoBackupLocationPublic = '位置：下载/金打细算/金打细算-自动备份.jx（卸载重装仍保留）';
const autoBackupLocationSandbox = '位置：应用沙盒内单文件（卸载后不保留）';

// ── 重装找回自动备份（DESIGN.md §19 · v1.2.x 票 03 · ADR-0018）────

// 「发现自动备份」确认框标题
const autoBackupFoundTitle = '发现自动备份';

// 确认框正文：备份时间 + 数量摘要。检测只看文件是否存在，
// 这份文件是不是用户自己的旧备份，留给用户凭摘要自行判断
String autoBackupFoundBody(String timeLabel, int ledgers, int envelopes, int txns) =>
    '发现 $timeLabel 的自动备份：$ledgers 个账本 · $envelopes 个信封 · '
    '$txns 笔流水。恢复会用这份备份覆盖当前数据，完成后直接进入主界面。';

// ── 统计页（DESIGN.md §8/§21 · v1.2.0 票 07）────

// 区间胶囊「编辑」底部弹层
const statsSegmentSheetTitle = '自定义区间胶囊';
const statsSegmentEditHint = '勾选要加进顶部胶囊的区间，「周」和「月」固定显示。';

// 周期直达列表弹层（点分页条标签弹出）
const statsPeriodSheetTitle = '跳到有流水的周期';
const statsPeriodPickerEmpty = '当前账本还没有流水，先去记一笔吧。';

// ── 透支腾挪（DESIGN.md §10/§13）─────────────

// 第一步：选要补的信封（多个透支时）
const fixOverspendPickTargetTitle = '补哪个信封？';
const fixOverspendPickTargetHint = '点一个还缺钱的信封';

// 第二步：选来源信封
String fixOverspendPickSourceTitle(String targetName) => '腾挪到「$targetName」';
const fixOverspendPickSourceHint = '点一个信封作为来源';

// 键盘副标题覆盖：从来源信封支出
String fixOverspendSourceSubtitle(
  String sourceName,
  double available, {
  required String symbol,
}) => '从「$sourceName」支出 · 剩 $symbol${money(available)}';

// 流水页透支提示条（点击「去补上」进入腾挪流程）
String overspendBannerSingle(
  String name,
  double total, {
  required String symbol,
}) => '「$name」还缺 $symbol${money(total)}';
String overspendBannerMulti(
  int count,
  double total, {
  required String symbol,
}) => '$count 个信封还缺 $symbol${money(total)}';

// ── 货币符号（v1.2.0 票 02 / ADR-0017）─────────

// 设置对话框正文：注明作用域（当前账本）与语义（只影响显示，不换算）
String currencyDialogBody(String ledgerName) =>
    '作用于当前账本「$ledgerName」；只是显示偏好，不会换算任何金额，历史记录原样保留。';

// 自定义输入框占位（容纳 HK$ 等复合符号）
const currencyCustomLabel = '自定义';
const currencyCustomHint = '输入 1–3 个字符，如 HK\$';

// 自定义输入去首尾空白后仍超长时的提示
const currencyTooLongHint = '去掉首尾空格后最多 3 个字符';

// 保存成功 toast
const currencySavedToast = '货币符号已更新';

// ── 使用说明页（DESIGN.md §9 · v1.2.x 票 04 · README「使用说明」节）────
// README 更新后需手动同步以下文案（拷问决策 2026-09-20：手写静态页，不引 markdown 渲染包）

// 信封预算法参考文章（sspai，App 内可点跳外部浏览器）
const kEnvelopeBudgetArticleUrl = 'https://sspai.com/post/61367';
const guideArticleLinkLabel = '摆脱超支困境，试试用这套「信封预算法」记账吧';

// 开篇卡正文
const guideEnvelopeIntroBody =
    '把收入先分进一个个「信封」，花销只从对应信封里出——这就是「信封预算法」。'
    '它让你只需要盯着自己手头的钱，新的收入也不容易打乱原来的预算。';

// 外链卡正文
const guideArticleIntroBody =
    '有关概念的讲解，少数派的这篇文章已经写得很详细，本项目的灵感也来自它——'
    '没接触过信封预算法的话，建议先读一读再回来上手。';

// 「让每一块钱都有分工」卡正文
const guideAllocationBody =
    '手头的钱和之后的收入，都先记进「待规划」，再把钱分配进各个信封；'
    '消费时从对应的信封里扣。这样你只需要专注手头的钱，不必被账户细分搅乱。';

// 三个操作步骤的说明（配 GIF 演示）
const guideStepIncomeDesc = '点首页顶部的「待规划」区域，输入金额，记一笔收入。';
const guideStepAllocateDesc = '按住「待规划」拖到信封上松手，输入金额，完成分配。';
const guideStepSpendDesc = '按住信封往下拖到底（或双击信封），输入金额，记录支出。';
const guideStepTransferDesc = '按住一个信封拖到另一个信封，完成预算转移。';

// 「信封的作用」卡正文
const guideEnvelopeRoleBody =
    '信封大致对应其他记账软件里的「账户」（微信钱包、支付宝、储蓄卡……）——'
    '但我们不提倡细分账户：所有手头的钱，都一并视为可以支配的钱。'
    '信封的价值是做灵活的预算，帮你厘清每笔钱的用处，尽量避免在某方面超支。';

// 信封优先级示例
const guideEnvelopePriorityBody =
    '可以试着给信封排个优先级，比如：当月刚需支出 > 时间不确定的重要支出 > '
    '娱乐支出 > 存款（仅供参考，按个人需求设定）。';

// 「灵活调整」卡正文
const guideFlexAdjustBody =
    '预算没有封口，随时可调。某项预算花超了（比如冲动消费），或高估了'
    '（比如划了 100 给交通却压根没出门），都可以临时把钱从一个信封转到另一个——'
    '让你时刻盯着预算，清楚接下来的消费要怎么调整。';

// 透支说明
const guideOverdraftBody =
    '信封允许透支（金额可以小于 0）。有信封透支时会有醒目提醒，促使你尽快补上。';

// 「预算周期与结转」卡正文
const guidePeriodBody =
    '预算周期是分配的有效时间区间。默认每个自然月 1 日开启新一期；'
    '也支持自定义起始日、以周为周期（从周一开始），或由你手动结束的自由周期。'
    '周期内分进信封的钱会累加为「已规划」，进信封详情页可见。';

// 进度条含义（README 的 LaTeX 公式改写成人话，票 04）
const guideProgressbarBody =
    '信封上的进度条，显示的是这个信封还剩几成预算：从已规划里扣掉已花掉的，'
    '剩下的就是还在信封里的部分。';

const guideCarryoverBody =
    '每个信封可以单独设定是否结转：开启时，周期结束后的剩余预算带入下一期；'
    '关闭时，剩余预算退回「待规划」。无论开关，透支都会延续到下一期。';

// 「数据安全」卡两条
const guidePrivacyBody =
    '可以按信封单独隐藏金额（信封详情页内设置）；「待规划」的金额在「我的」页设置是否隐藏。';
const guideDataSafetyBody =
    'App 没有任何网络连接，数据都在你的设备上，需要你自主备份管理；'
    '开发者不会获取你的任何数据。';

// 外链打不开的 toast 兜底（关于页/使用说明页共用）
String linkOpenFailedToast(String url) => '没能打开浏览器，请手动访问 $url';
