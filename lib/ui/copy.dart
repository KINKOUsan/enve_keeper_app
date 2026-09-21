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
const autoBackupLocationPublic = '位置：下载/金打细算/金打细算-自动备份.jx';
const autoBackupLocationSandbox = '位置：应用沙盒内单文件';

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
// 以下正文逐字忠实还原 README「使用说明」节原文（用户要求 2026-09-21），
// 仅排版结构化；唯一改写处是工单明示的 LaTeX 公式（guideFormulaPlain）。
// README 更新后需手动同步以下文案（拷问决策 2026-09-20：手写静态页，不引 markdown 渲染包）

// 信封预算法参考文章（sspai，开篇段【标题】内嵌链接，页内可点跳外部浏览器）
const kEnvelopeBudgetArticleUrl = 'https://sspai.com/post/61367';

// 开篇段原文（按内嵌链接拆成 前段/链接标题/后段 三段拼装）
const guideIntroBeforeLink = '什么是“信封预算法”？有关概念在【';
const guideArticleLinkLabel = '摆脱超支困境，试试用这套「信封预算法」记账吧';
const guideIntroAfterLink =
    '】已经讲得很详细，本项目的灵感来源也来自这篇文章，笔者建议读者去看看，'
    '没接触过信封预算法的人看了之后或许能感受到这种方法的魅力所在。'
    '下面笔者结合个人理解与「金打细算」的具体操作，给出简单使用说明：';

// 「让得到的每一块钱都做好「分工」」节正文
const guideAllocationBody =
    '「金打细算」希望使用者可以将自己手头上已有的可支配的钱，以及后续得到的'
    '收入都先进入「待规划」，然后再将这些钱分配进各个信封，各类消费将由使用者'
    '决定使用哪个信封，然后从对应的信封内扣除金额。这样做的好处是，使用者只需'
    '专注于自己手头上已有的钱，且后续有新的收入时不容易干扰原来所做的预算。';

// 三个操作步骤（原文：粗体标签 + 正文，配 GIF 演示）
const guideStepIncomeLabel = '记录收入';
const guideStepIncomeDesc = '点击首页顶部的「待规划」区域，输入金额数记录收入；';
const guideStepAllocateLabel = '分配金额';
const guideStepAllocateDesc = '从「待规划」开始拖拽，将钱拖拽进信封，然后输入分配金额，完成分配；';
const guideStepSpendLabel = '记录消费';
const guideStepSpendDesc = '从使用者想要消费的信封开始拖拽，将钱拖到底部，或双击对应信封，输入消费金额，记录支出。';
const guideStepTransferLabel = '信封之间转移';
const guideStepTransferDesc = '从一个信封开始拖拽，将钱拖到另一个信封，完成预算转移。';

// 「设置信封的作用」节两段
const guideEnvelopeRoleBody =
    '「信封」这一容器概念大致对应于其他记账软件的各方账户（如微信钱包、支付宝、'
    '各大银行的储蓄卡等）——但其实很不一样，「金打细算」不提倡使用者细分各种'
    '账户的钱，这些钱应当全部一并视为手头可以支配的钱。信封的关键作用是做灵活'
    '预算，方便使用者厘清手头的钱发挥的作用，尽力避免在某些方面超支，以及避免'
    '使用者在临时调配时感到混乱。';

const guideEnvelopePriorityBody =
    '使用者可以尝试给信封定下优先级，比如【当月刚需支出 > 时间不确定的重要支出 '
    '> 娱乐支出 > 存款】（根据个人需求设定信封，仅作参考）。';

// 「灵活调整预算」节两段 + 转移步骤
const guideFlexAdjustBody =
    '预算信封没有封口，可以随时调整。做预算很可能会出现对某项预算过于乐观的'
    '情况（比如冲动消费多花了一些钱），也可能会高估某项预算（比如划分了100给'
    '交通，实际上根本不出门）。莫慌，可以临时将预算从一个信封转到另一个信封，'
    '这样做的好处在于让使用者时刻注目预算，更清楚接下来的消费行为要做出什么改变。';

const guideOverdraftBody =
    '信封是可透支的，即金额数可以小于0。若存在信封处于透支状态，软件会有醒目'
    '提醒，促使补上透支。';

// 「预算周期与结转」节：小标题 + 原文段
const guidePeriodHeading = '预算周期';
const guidePeriodBody =
    '预算周期是「金打细算」设定的分配有效时间区间，默认以每个自然月的 1 日开始'
    '新的周期，同时软件也提供让用户自定义每个月的起始日，也支持以周为一个周期'
    '（从周一开始），甚至支持自由周期——由用户手动结束当前周期。';

// 进度条句（原文）+ 公式人话（票 04 唯一改写处：LaTeX → 一句人话，接在冒号后）
const guideProgressbarBody =
    '在预算周期内，每个信封从「待规划」转入金额后，都将同时累加「已规划」，'
    '即这个信封在周期内从「待规划」进过多少钱，单击信封进入信封详情页可见。'
    '首页的信封上显示的进度条显示的进度为：';
const guideFormulaPlain = '已规划减去已支出，再除以已规划，也就是这个信封还剩几成预算。';

const guideCarryoverHeading = '结转';
const guideCarryoverBody =
    '可以对每个信封单独设定是否结转至下一个周期。结转的意思是，当一个预算周期'
    '结束时，将信封里剩余的预算继承到下一个周期；若选择不结转，则对应的信封在'
    '预算周期结束时，剩余的预算将退回至「待规划」。';

const guideCarryoverOverdraftBody =
    '另外，若信封处于透支状态，则无论是否开启结转，透支状况都将延续至下一周期。';

// 「数据安全」节两条（原文：粗体标签 + 正文）
const guidePrivacyLabel = '隐藏首页显示的金额数目';
const guidePrivacyBody =
    '可对每个信封单独设定是否隐藏，进入信封详情页可设置；特别地，「待规划」的'
    '数目在「我的」页面设置是否隐藏。';
const guideDataSafetyLabel = '用户数据';
const guideDataSafetyBody =
    '软件不存在网络连接，其数据需要用户自主管理，开发者绝不会获取用户的数据。';

// 外链打不开的 toast 兜底（关于页/使用说明页共用）
String linkOpenFailedToast(String url) => '没能打开浏览器，请手动访问 $url';

// ── 支持页（DESIGN.md §9 · v1.2.x 票 05）────

// 支持页开篇一句话
const supportIntroBody = '金打细算完全免费，如果它帮到了你，可以请作者喝一杯。';
