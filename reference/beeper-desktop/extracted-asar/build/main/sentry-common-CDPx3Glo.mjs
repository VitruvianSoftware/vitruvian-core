import k from "os";
import { g as T, a as D } from "./_commonjsHelpers-CBUqixCJ.mjs";
import O from "./package-CIHfweXK.mjs";
import { S as q } from "./sentry-enabled-COAVq6nC.mjs";
(function () {
  try {
    var e =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    e.SENTRY_RELEASE = { id: "4.3.209" };
    var a = new e.Error().stack;
    a &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[a] = "9fd24b41-9df2-47d5-9666-46cbeab67d90"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-9fd24b41-9df2-47d5-9666-46cbeab67d90"));
  } catch {}
})();
var f, v;
function A() {
  if (v) return f;
  v = 1;
  const e = "[a-fA-F\\d:]",
    a = (s) =>
      s && s.includeBoundaries
        ? `(?:(?<=\\s|^)(?=${e})|(?<=${e})(?=\\s|$))`
        : "",
    t =
      "(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]\\d|\\d)(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]\\d|\\d)){3}",
    r = "[a-fA-F\\d]{1,4}",
    i = `
(?:
(?:${r}:){7}(?:${r}|:)|                                    // 1:2:3:4:5:6:7::  1:2:3:4:5:6:7:8
(?:${r}:){6}(?:${t}|:${r}|:)|                             // 1:2:3:4:5:6::    1:2:3:4:5:6::8   1:2:3:4:5:6::8  1:2:3:4:5:6::1.2.3.4
(?:${r}:){5}(?::${t}|(?::${r}){1,2}|:)|                   // 1:2:3:4:5::      1:2:3:4:5::7:8   1:2:3:4:5::8    1:2:3:4:5::7:1.2.3.4
(?:${r}:){4}(?:(?::${r}){0,1}:${t}|(?::${r}){1,3}|:)| // 1:2:3:4::        1:2:3:4::6:7:8   1:2:3:4::8      1:2:3:4::6:7:1.2.3.4
(?:${r}:){3}(?:(?::${r}){0,2}:${t}|(?::${r}){1,4}|:)| // 1:2:3::          1:2:3::5:6:7:8   1:2:3::8        1:2:3::5:6:7:1.2.3.4
(?:${r}:){2}(?:(?::${r}){0,3}:${t}|(?::${r}){1,5}|:)| // 1:2::            1:2::4:5:6:7:8   1:2::8          1:2::4:5:6:7:1.2.3.4
(?:${r}:){1}(?:(?::${r}){0,4}:${t}|(?::${r}){1,6}|:)| // 1::              1::3:4:5:6:7:8   1::8            1::3:4:5:6:7:1.2.3.4
(?::(?:(?::${r}){0,5}:${t}|(?::${r}){1,7}|:))             // ::2:3:4:5:6:7:8  ::2:3:4:5:6:7:8  ::8             ::1.2.3.4
)(?:%[0-9a-zA-Z]{1,})?                                             // %eth0            %1
`
      .replace(/\s*\/\/.*$/gm, "")
      .replace(/\n/g, "")
      .trim(),
    n = new RegExp(`(?:^${t}$)|(?:^${i}$)`),
    u = new RegExp(`^${t}$`),
    d = new RegExp(`^${i}$`),
    g = (s) =>
      s && s.exact
        ? n
        : new RegExp(`(?:${a(s)}${t}${a(s)})|(?:${a(s)}${i}${a(s)})`, "g");
  return (
    (g.v4 = (s) => (s && s.exact ? u : new RegExp(`${a(s)}${t}${a(s)}`, "g"))),
    (g.v6 = (s) => (s && s.exact ? d : new RegExp(`${a(s)}${i}${a(s)}`, "g"))),
    (f = g),
    f
  );
}
const I = JSON.parse(
    '["aaa","aarp","abb","abbott","abbvie","abc","able","abogado","abudhabi","ac","academy","accenture","accountant","accountants","aco","actor","ad","ads","adult","ae","aeg","aero","aetna","af","afl","africa","ag","agakhan","agency","ai","aig","airbus","airforce","airtel","akdn","al","alibaba","alipay","allfinanz","allstate","ally","alsace","alstom","am","amazon","americanexpress","americanfamily","amex","amfam","amica","amsterdam","analytics","android","anquan","anz","ao","aol","apartments","app","apple","aq","aquarelle","ar","arab","aramco","archi","army","arpa","art","arte","as","asda","asia","associates","at","athleta","attorney","au","auction","audi","audible","audio","auspost","author","auto","autos","aw","aws","ax","axa","az","azure","ba","baby","baidu","banamex","band","bank","bar","barcelona","barclaycard","barclays","barefoot","bargains","baseball","basketball","bauhaus","bayern","bb","bbc","bbt","bbva","bcg","bcn","bd","be","beats","beauty","beer","bentley","berlin","best","bestbuy","bet","bf","bg","bh","bharti","bi","bible","bid","bike","bing","bingo","bio","biz","bj","black","blackfriday","blockbuster","blog","bloomberg","blue","bm","bms","bmw","bn","bnpparibas","bo","boats","boehringer","bofa","bom","bond","boo","book","booking","bosch","bostik","boston","bot","boutique","box","br","bradesco","bridgestone","broadway","broker","brother","brussels","bs","bt","build","builders","business","buy","buzz","bv","bw","by","bz","bzh","ca","cab","cafe","cal","call","calvinklein","cam","camera","camp","canon","capetown","capital","capitalone","car","caravan","cards","care","career","careers","cars","casa","case","cash","casino","cat","catering","catholic","cba","cbn","cbre","cc","cd","center","ceo","cern","cf","cfa","cfd","cg","ch","chanel","channel","charity","chase","chat","cheap","chintai","christmas","chrome","church","ci","cipriani","circle","cisco","citadel","citi","citic","city","ck","cl","claims","cleaning","click","clinic","clinique","clothing","cloud","club","clubmed","cm","cn","co","coach","codes","coffee","college","cologne","com","commbank","community","company","compare","computer","comsec","condos","construction","consulting","contact","contractors","cooking","cool","coop","corsica","country","coupon","coupons","courses","cpa","cr","credit","creditcard","creditunion","cricket","crown","crs","cruise","cruises","cu","cuisinella","cv","cw","cx","cy","cymru","cyou","cz","dad","dance","data","date","dating","datsun","day","dclk","dds","de","deal","dealer","deals","degree","delivery","dell","deloitte","delta","democrat","dental","dentist","desi","design","dev","dhl","diamonds","diet","digital","direct","directory","discount","discover","dish","diy","dj","dk","dm","dnp","do","docs","doctor","dog","domains","dot","download","drive","dtv","dubai","dunlop","dupont","durban","dvag","dvr","dz","earth","eat","ec","eco","edeka","edu","education","ee","eg","email","emerck","energy","engineer","engineering","enterprises","epson","equipment","er","ericsson","erni","es","esq","estate","et","eu","eurovision","eus","events","exchange","expert","exposed","express","extraspace","fage","fail","fairwinds","faith","family","fan","fans","farm","farmers","fashion","fast","fedex","feedback","ferrari","ferrero","fi","fidelity","fido","film","final","finance","financial","fire","firestone","firmdale","fish","fishing","fit","fitness","fj","fk","flickr","flights","flir","florist","flowers","fly","fm","fo","foo","food","football","ford","forex","forsale","forum","foundation","fox","fr","free","fresenius","frl","frogans","frontier","ftr","fujitsu","fun","fund","furniture","futbol","fyi","ga","gal","gallery","gallo","gallup","game","games","gap","garden","gay","gb","gbiz","gd","gdn","ge","gea","gent","genting","george","gf","gg","ggee","gh","gi","gift","gifts","gives","giving","gl","glass","gle","global","globo","gm","gmail","gmbh","gmo","gmx","gn","godaddy","gold","goldpoint","golf","goo","goodyear","goog","google","gop","got","gov","gp","gq","gr","grainger","graphics","gratis","green","gripe","grocery","group","gs","gt","gu","gucci","guge","guide","guitars","guru","gw","gy","hair","hamburg","hangout","haus","hbo","hdfc","hdfcbank","health","healthcare","help","helsinki","here","hermes","hiphop","hisamitsu","hitachi","hiv","hk","hkt","hm","hn","hockey","holdings","holiday","homedepot","homegoods","homes","homesense","honda","horse","hospital","host","hosting","hot","hotels","hotmail","house","how","hr","hsbc","ht","hu","hughes","hyatt","hyundai","ibm","icbc","ice","icu","id","ie","ieee","ifm","ikano","il","im","imamat","imdb","immo","immobilien","in","inc","industries","infiniti","info","ing","ink","institute","insurance","insure","int","international","intuit","investments","io","ipiranga","iq","ir","irish","is","ismaili","ist","istanbul","it","itau","itv","jaguar","java","jcb","je","jeep","jetzt","jewelry","jio","jll","jm","jmp","jnj","jo","jobs","joburg","jot","joy","jp","jpmorgan","jprs","juegos","juniper","kaufen","kddi","ke","kerryhotels","kerrylogistics","kerryproperties","kfh","kg","kh","ki","kia","kids","kim","kindle","kitchen","kiwi","km","kn","koeln","komatsu","kosher","kp","kpmg","kpn","kr","krd","kred","kuokgroup","kw","ky","kyoto","kz","la","lacaixa","lamborghini","lamer","lancaster","land","landrover","lanxess","lasalle","lat","latino","latrobe","law","lawyer","lb","lc","lds","lease","leclerc","lefrak","legal","lego","lexus","lgbt","li","lidl","life","lifeinsurance","lifestyle","lighting","like","lilly","limited","limo","lincoln","link","lipsy","live","living","lk","llc","llp","loan","loans","locker","locus","lol","london","lotte","lotto","love","lpl","lplfinancial","lr","ls","lt","ltd","ltda","lu","lundbeck","luxe","luxury","lv","ly","ma","madrid","maif","maison","makeup","man","management","mango","map","market","marketing","markets","marriott","marshalls","mattel","mba","mc","mckinsey","md","me","med","media","meet","melbourne","meme","memorial","men","menu","merckmsd","mg","mh","miami","microsoft","mil","mini","mint","mit","mitsubishi","mk","ml","mlb","mls","mm","mma","mn","mo","mobi","mobile","moda","moe","moi","mom","monash","money","monster","mormon","mortgage","moscow","moto","motorcycles","mov","movie","mp","mq","mr","ms","msd","mt","mtn","mtr","mu","museum","music","mv","mw","mx","my","mz","na","nab","nagoya","name","navy","nba","nc","ne","nec","net","netbank","netflix","network","neustar","new","news","next","nextdirect","nexus","nf","nfl","ng","ngo","nhk","ni","nico","nike","nikon","ninja","nissan","nissay","nl","no","nokia","norton","now","nowruz","nowtv","np","nr","nra","nrw","ntt","nu","nyc","nz","obi","observer","office","okinawa","olayan","olayangroup","ollo","om","omega","one","ong","onl","online","ooo","open","oracle","orange","org","organic","origins","osaka","otsuka","ott","ovh","pa","page","panasonic","paris","pars","partners","parts","party","pay","pccw","pe","pet","pf","pfizer","pg","ph","pharmacy","phd","philips","phone","photo","photography","photos","physio","pics","pictet","pictures","pid","pin","ping","pink","pioneer","pizza","pk","pl","place","play","playstation","plumbing","plus","pm","pn","pnc","pohl","poker","politie","porn","post","pr","pramerica","praxi","press","prime","pro","prod","productions","prof","progressive","promo","properties","property","protection","pru","prudential","ps","pt","pub","pw","pwc","py","qa","qpon","quebec","quest","racing","radio","re","read","realestate","realtor","realty","recipes","red","redstone","redumbrella","rehab","reise","reisen","reit","reliance","ren","rent","rentals","repair","report","republican","rest","restaurant","review","reviews","rexroth","rich","richardli","ricoh","ril","rio","rip","ro","rocks","rodeo","rogers","room","rs","rsvp","ru","rugby","ruhr","run","rw","rwe","ryukyu","sa","saarland","safe","safety","sakura","sale","salon","samsclub","samsung","sandvik","sandvikcoromant","sanofi","sap","sarl","sas","save","saxo","sb","sbi","sbs","sc","scb","schaeffler","schmidt","scholarships","school","schule","schwarz","science","scot","sd","se","search","seat","secure","security","seek","select","sener","services","seven","sew","sex","sexy","sfr","sg","sh","shangrila","sharp","shell","shia","shiksha","shoes","shop","shopping","shouji","show","si","silk","sina","singles","site","sj","sk","ski","skin","sky","skype","sl","sling","sm","smart","smile","sn","sncf","so","soccer","social","softbank","software","sohu","solar","solutions","song","sony","soy","spa","space","sport","spot","sr","srl","ss","st","stada","staples","star","statebank","statefarm","stc","stcgroup","stockholm","storage","store","stream","studio","study","style","su","sucks","supplies","supply","support","surf","surgery","suzuki","sv","swatch","swiss","sx","sy","sydney","systems","sz","tab","taipei","talk","taobao","target","tatamotors","tatar","tattoo","tax","taxi","tc","tci","td","tdk","team","tech","technology","tel","temasek","tennis","teva","tf","tg","th","thd","theater","theatre","tiaa","tickets","tienda","tips","tires","tirol","tj","tjmaxx","tjx","tk","tkmaxx","tl","tm","tmall","tn","to","today","tokyo","tools","top","toray","toshiba","total","tours","town","toyota","toys","tr","trade","trading","training","travel","travelers","travelersinsurance","trust","trv","tt","tube","tui","tunes","tushu","tv","tvs","tw","tz","ua","ubank","ubs","ug","uk","unicom","university","uno","uol","ups","us","uy","uz","va","vacations","vana","vanguard","vc","ve","vegas","ventures","verisign","vermögensberater","vermögensberatung","versicherung","vet","vg","vi","viajes","video","vig","viking","villas","vin","vip","virgin","visa","vision","viva","vivo","vlaanderen","vn","vodka","volvo","vote","voting","voto","voyage","vu","wales","walmart","walter","wang","wanggou","watch","watches","weather","weatherchannel","webcam","weber","website","wed","wedding","weibo","weir","wf","whoswho","wien","wiki","williamhill","win","windows","wine","winners","wme","wolterskluwer","woodside","work","works","world","wow","ws","wtc","wtf","xbox","xerox","xihuan","xin","xxx","xyz","yachts","yahoo","yamaxun","yandex","ye","yodobashi","yoga","yokohama","you","youtube","yt","yun","za","zappos","zara","zero","zip","zm","zone","zuerich","zw","ελ","ευ","бг","бел","дети","ею","католик","ком","мкд","мон","москва","онлайн","орг","рус","рф","сайт","срб","укр","қаз","հայ","ישראל","קום","ابوظبي","ارامكو","الاردن","البحرين","الجزائر","السعودية","العليان","المغرب","امارات","ایران","بارت","بازار","بيتك","بھارت","تونس","سودان","سورية","شبكة","عراق","عرب","عمان","فلسطين","قطر","كاثوليك","كوم","مصر","مليسيا","موريتانيا","موقع","همراه","پاکستان","ڀارت","कॉम","नेट","भारत","भारतम्","भारोत","संगठन","বাংলা","ভারত","ভাৰত","ਭਾਰਤ","ભારત","ଭାରତ","இந்தியா","இலங்கை","சிங்கப்பூர்","భారత్","ಭಾರತ","ഭാരതം","ලංකා","คอม","ไทย","ລາວ","გე","みんな","アマゾン","クラウド","グーグル","コム","ストア","セール","ファッション","ポイント","世界","中信","中国","中國","中文网","亚马逊","企业","佛山","信息","健康","八卦","公司","公益","台湾","台灣","商城","商店","商标","嘉里","嘉里大酒店","在线","大拿","天主教","娱乐","家電","广东","微博","慈善","我爱你","手机","招聘","政务","政府","新加坡","新闻","时尚","書籍","机构","淡马锡","游戏","澳門","点看","移动","组织机构","网址","网店","网站","网络","联通","谷歌","购物","通販","集团","電訊盈科","飞利浦","食品","餐厅","香格里拉","香港","닷넷","닷컴","삼성","한국"]',
  ),
  P = {},
  C = Object.freeze(
    Object.defineProperty({ __proto__: null, default: P }, Symbol.toStringTag, {
      value: "Module",
    }),
  ),
  M = T(C);
var b, w;
function K() {
  if (w) return b;
  w = 1;
  const e = A(),
    a = I,
    t = e.v4().source,
    r = e.v6().source,
    i = "(?:(?:[a-z\\u00a1-\\uffff0-9][-_]*)*[a-z\\u00a1-\\uffff0-9]+)",
    n = "(?:\\.(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)*",
    u = "(?:[a-z\\u00a1-\\uffff]{2,})",
    d = `(?:${a.sort((o, p) => p.length - o.length).join("|")})`,
    g = "(?::\\d{2,5})?";
  let s, y;
  return (
    (b = (o) => {
      o = {
        re2: !0,
        exact: !1,
        strict: !1,
        auth: !1,
        localhost: !0,
        parens: !1,
        apostrophes: !1,
        trailingPeriod: !1,
        ipv4: !0,
        ipv6: !0,
        returnString: !1,
        ...o,
      };
      const p =
          o.re2 && y !== !1
            ? (() => {
                if (typeof s == "function") return s;
                try {
                  return ((s = M), typeof s == "function" ? s : RegExp);
                } catch {
                  return ((y = !1), RegExp);
                }
              })()
            : RegExp,
        R = `(?:(?:[a-z]+:)?//)${o.strict ? "" : "?"}`,
        _ = o.auth ? "(?:\\S+(?::\\S*)?@)?" : "",
        z = `(?:\\.${o.strict ? u : o.tlds ? `(?:${o.tlds.sort((N, S) => S.length - N.length).join("|")})` : d})${o.trailingPeriod ? "\\.?" : ""}`;
      let m = '\\s"';
      (o.parens || (m += "\\)"), o.apostrophes || (m += "'"));
      const j = o.trailingPeriod
        ? `(?:[/?#][^${m}]*)?`
        : `(?:(?:[/?#][^${m}]*[^${m}.?!])|[/])?`;
      let c = `(?:${R}|www\\.)${_}(?:`;
      return (
        o.localhost && (c += "localhost|"),
        o.ipv4 && (c += `${t}|`),
        o.ipv6 && (c += `${r}|`),
        (c += `${i}${n}${z})${g}${j}`),
        o.returnString ? c : o.exact ? new p(`(?:^${c}$)`, "i") : new p(c, "ig")
      );
    }),
    b
  );
}
var U = K();
const H = D(U),
  B =
    "https://22069267152d0556896061c5c67463fc@o248881.ingest.us.sentry.io/4510439832551424",
  F = (e) =>
    e
      .replace(/^\([^)]*\): \w+: /, "")
      .replace(/^\w+ failed: /, "")
      .replace(/^COM\.BEEPER\.[A-Z_]+(?: \(HTTP \d+\))?: /, ""),
  E = /^(\w+) failed: /,
  L = /^\(([^)]*)\): /,
  x = /\b((?:M_|COM\.BEEPER\.|FI\.MAU\.|NET\.MAUNIUM\.)[A-Z0-9_.]+)/,
  $ = (e) =>
    e
      .replace(/[!#][^\s:]+:[^\s,)]+/g, "<roomid>")
      .replace(/@[^\s:]+:[^\s,)]+/g, "<userid>")
      .replace(/\$[A-Za-z0-9_-]{8,}(?::[^\s,)]+)?/g, "<eventid>"),
  W = (e) =>
    $(F(e))
      .replace(/\b[0-9a-f]{8,}\b/gi, "<hex>")
      .replace(/(?<!HTTP )\b\d+\b/g, "<n>")
      .trim()
      .slice(0, 120),
  te = (e) => e?.canRetry === !0,
  se = (e) => {
    const a = e;
    if (!(!a || typeof a != "object"))
      return x.exec(`${a.internalError ?? ""}
${a.message ?? ""}`)?.[1];
  },
  Z = (e) => {
    if (e.name !== "RelayedError") return { inner: e };
    const a = e.tag || L.exec(e.message ?? "")?.[1],
      t = e.cause;
    return {
      tag: a && a !== "?" ? a : void 0,
      inner: t && typeof t == "object" ? t : e,
    };
  },
  G = (e) => {
    const a = e;
    if (!a || typeof a != "object") return;
    const { tag: t, inner: r } = Z(a),
      i = typeof r.message == "string" ? r.message : "",
      n =
        r.name === "SDKError" ||
        typeof r.internalError == "string" ||
        E.test(i);
    if (!n && !t) return;
    const u =
        r.methodName || E.exec(i)?.[1] || (n ? "unknown" : r.name || "Error"),
      d = x.exec(`${r.internalError ?? ""}
${i}`)?.[1];
    return { tag: t, method: u, cause: d ?? W(i) };
  },
  { username: h } = "userInfo" in k ? k.userInfo() : { username: "" },
  Y = H({ strict: !0 }),
  l = (e) => {
    if (!e || typeof e != "string") return e;
    const t = (h && h.length > 2 ? e.replaceAll?.(h, "$USER") : e)
      .replace(Y, "<scrubbed_url>")
      .replace(
        /(iMessage|SMS|RCS);[-+];(chat)?\+?[\d -]+/g,
        "<scrubbed_imsg_id>",
      )
      .replace(/\d+@s\.whatsapp\.net/g, "<scrubbed_wa_id>")
      .replace(/\+\d[\d ().-]{5,}\d/g, "<scrubbed_phone>");
    return $(t);
  },
  J = (e) =>
    e
      .replace(/(?:[A-Za-z]:\\|[/\\])[\s\S]*$/, "<path>")
      .replace(/\b\d+\b/g, "<n>")
      .trim()
      .slice(0, 120);
function V(e) {
  return (
    e &&
    (e.exception?.values?.forEach((a) => {
      (a.stacktrace?.frames?.forEach((t) => {
        delete t.module;
      }),
        a?.value && (a.value = l(a.value)));
    }),
    typeof e.message == "string" && (e.message = l(e.message)),
    typeof e.logentry?.message == "string" &&
      (e.logentry.message = l(e.logentry.message)),
    e.breadcrumbs?.forEach((a) => {
      !a?.message ||
        (a.type === "ui" && a.category === "electron" && a.level === "info") ||
        (a.message = l(a.message));
    }),
    e)
  );
}
function Q(e) {
  const { data: a } = e;
  if (!a) return e;
  const t = { data: { ...a }, ...e };
  for (const r of Object.keys(a))
    typeof a[r] == "string" && (t.data[r] = l(a[r]));
  return t;
}
const oe = {
  enabled: q,
  dsn: B,
  release: O.version,
  environment: "production",
  tracesSampleRate: 1,
  tracePropagationTargets: [
    /^https?:\/\/(localhost|127\.0\.0\.1)/,
    /^fileproxy:\/\//,
    /^https:\/\/(api\.)?beeper(-staging|-dev)?\.com/,
    /^https:\/\/(m\.)?texts\.com/,
    /^\//,
  ],
  beforeBreadcrumb: Q,
  beforeSend: (e, a) => {
    const t = V(e),
      r = G(a?.originalException);
    if (t && r) {
      const i = l(r.cause);
      ((t.fingerprint = [
        "{{ default }}",
        "sdk-error",
        r.tag,
        r.method,
        i,
      ].filter(Boolean)),
        (t.tags = {
          ...t.tags,
          sdk_method: r.method,
          sdk_cause: i,
          ...(r.tag && { sdk_call: r.tag }),
        }));
      for (const n of t.exception?.values ?? [])
        n.type === "SDKError"
          ? (n.type = `SDKError(${r.method})`)
          : n.type === "RelayedError" &&
            r.tag &&
            (n.type = `RelayedError(${r.tag})`);
    } else if (t) {
      const i = t.exception?.values?.find(
        (n) => n.type === "SqliteError" && n.value,
      );
      i?.value && (t.fingerprint = ["{{ default }}", "sqlite", J(i.value)]);
    }
    return t;
  },
  ignoreErrors: [
    "write EIO",
    "write EPIPE",
    "ERR_CONNECTION_RESET",
    "ERR_NETWORK_IO_SUSPENDED",
    "ERR_NAME_NOT_RESOLVED",
    "ERR_NETWORK_CHANGED",
    "ERR_INTERNET_DISCONNECTED",
    "ENETUNREACH",
    "Network is unreachable",
    "EHOSTUNREACH",
    "ETIMEDOUT",
    "getaddrinfo ENOTFOUND",
    "ECONNABORTED",
    "M_UNKNOWN (HTTP 502)",
    "M_UNKNOWN (HTTP 503)",
    "M_UNKNOWN (HTTP 504)",
    "recovery code is incorrect",
  ],
};
export { se as a, oe as b, te as i, l as s, h as u };
//# sourceMappingURL=sentry-common-CDPx3Glo.mjs.map
