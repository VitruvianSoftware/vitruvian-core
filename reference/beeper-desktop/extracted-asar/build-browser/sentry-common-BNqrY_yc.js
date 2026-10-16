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
    var t = new e.Error().stack;
    t &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[t] = "c1a9f922-a3d5-4b46-a2d3-165e6c6f6948"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-c1a9f922-a3d5-4b46-a2d3-165e6c6f6948"));
  } catch {}
})();
function Xo(e) {
  return e && e.__esModule && Object.prototype.hasOwnProperty.call(e, "default")
    ? e.default
    : e;
}
var ho = { exports: {} },
  ie = (ho.exports = {}),
  ve,
  ge;
function gt() {
  throw new Error("setTimeout has not been defined");
}
function bt() {
  throw new Error("clearTimeout has not been defined");
}
(function () {
  try {
    typeof setTimeout == "function" ? (ve = setTimeout) : (ve = gt);
  } catch {
    ve = gt;
  }
  try {
    typeof clearTimeout == "function" ? (ge = clearTimeout) : (ge = bt);
  } catch {
    ge = bt;
  }
})();
function mo(e) {
  if (ve === setTimeout) return setTimeout(e, 0);
  if ((ve === gt || !ve) && setTimeout)
    return ((ve = setTimeout), setTimeout(e, 0));
  try {
    return ve(e, 0);
  } catch {
    try {
      return ve.call(null, e, 0);
    } catch {
      return ve.call(this, e, 0);
    }
  }
}
function ea(e) {
  if (ge === clearTimeout) return clearTimeout(e);
  if ((ge === bt || !ge) && clearTimeout)
    return ((ge = clearTimeout), clearTimeout(e));
  try {
    return ge(e);
  } catch {
    try {
      return ge.call(null, e);
    } catch {
      return ge.call(this, e);
    }
  }
}
var be = [],
  Te = !1,
  Re,
  ze = -1;
function ra() {
  !Te ||
    !Re ||
    ((Te = !1),
    Re.length ? (be = Re.concat(be)) : (ze = -1),
    be.length && vo());
}
function vo() {
  if (!Te) {
    var e = mo(ra);
    Te = !0;
    for (var t = be.length; t;) {
      for (Re = be, be = []; ++ze < t;) Re && Re[ze].run();
      ((ze = -1), (t = be.length));
    }
    ((Re = null), (Te = !1), ea(e));
  }
}
ie.nextTick = function (e) {
  var t = new Array(arguments.length - 1);
  if (arguments.length > 1)
    for (var r = 1; r < arguments.length; r++) t[r - 1] = arguments[r];
  (be.push(new go(e, t)), be.length === 1 && !Te && mo(vo));
};
function go(e, t) {
  ((this.fun = e), (this.array = t));
}
go.prototype.run = function () {
  this.fun.apply(null, this.array);
};
ie.title = "browser";
ie.browser = !0;
ie.env = {};
ie.argv = [];
ie.version = "";
ie.versions = {};
function Ae() {}
ie.on = Ae;
ie.addListener = Ae;
ie.once = Ae;
ie.off = Ae;
ie.removeListener = Ae;
ie.removeAllListeners = Ae;
ie.emit = Ae;
ie.prependListener = Ae;
ie.prependOnceListener = Ae;
ie.listeners = function (e) {
  return [];
};
ie.binding = function (e) {
  throw new Error("process.binding is not supported");
};
ie.cwd = function () {
  return "/";
};
ie.chdir = function (e) {
  throw new Error("process.chdir is not supported");
};
ie.umask = function () {
  return 0;
};
var ta = ho.exports;
const na = Xo(ta),
  Ks = globalThis.MACHINE_ID;
var Me = {
  os_userInfo: { username: "$username" },
  os_release: "25.6.0",
  os_arch: "arm64",
  os_homedir: "/Users/builder",
  os_platform: "darwin",
};
const oa = () => "/tmp",
  aa = () => Me.os_userInfo,
  ia = () => Me.os_release,
  sa = () => Me.os_arch,
  la = () => Me.os_platform,
  fa = () => Me.os_homedir,
  He = {
    tmpdir: oa,
    homedir: fa,
    platform: la,
    arch: sa,
    release: ia,
    userInfo: aa,
  };
var Ke =
  typeof globalThis < "u"
    ? globalThis
    : typeof window < "u"
      ? window
      : typeof global < "u"
        ? global
        : typeof self < "u"
          ? self
          : {};
function Ve(e) {
  return e && e.__esModule && Object.prototype.hasOwnProperty.call(e, "default")
    ? e.default
    : e;
}
function ua(e) {
  if (Object.prototype.hasOwnProperty.call(e, "__esModule")) return e;
  var t = e.default;
  if (typeof t == "function") {
    var r = function a() {
      var m = !1;
      try {
        m = this instanceof a;
      } catch {}
      return m
        ? Reflect.construct(t, arguments, this.constructor)
        : t.apply(this, arguments);
    };
    r.prototype = t.prototype;
  } else r = {};
  return (
    Object.defineProperty(r, "__esModule", { value: !0 }),
    Object.keys(e).forEach(function (a) {
      var m = Object.getOwnPropertyDescriptor(e, a);
      Object.defineProperty(
        r,
        a,
        m.get
          ? m
          : {
              enumerable: !0,
              get: function () {
                return e[a];
              },
            },
      );
    }),
    r
  );
}
var lr, Zt;
function ca() {
  if (Zt) return lr;
  Zt = 1;
  const e = "[a-fA-F\\d:]",
    t = (c) =>
      c && c.includeBoundaries
        ? `(?:(?<=\\s|^)(?=${e})|(?<=${e})(?=\\s|$))`
        : "",
    r =
      "(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]\\d|\\d)(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]\\d|\\d)){3}",
    a = "[a-fA-F\\d]{1,4}",
    m = `
(?:
(?:${a}:){7}(?:${a}|:)|                                    // 1:2:3:4:5:6:7::  1:2:3:4:5:6:7:8
(?:${a}:){6}(?:${r}|:${a}|:)|                             // 1:2:3:4:5:6::    1:2:3:4:5:6::8   1:2:3:4:5:6::8  1:2:3:4:5:6::1.2.3.4
(?:${a}:){5}(?::${r}|(?::${a}){1,2}|:)|                   // 1:2:3:4:5::      1:2:3:4:5::7:8   1:2:3:4:5::8    1:2:3:4:5::7:1.2.3.4
(?:${a}:){4}(?:(?::${a}){0,1}:${r}|(?::${a}){1,3}|:)| // 1:2:3:4::        1:2:3:4::6:7:8   1:2:3:4::8      1:2:3:4::6:7:1.2.3.4
(?:${a}:){3}(?:(?::${a}){0,2}:${r}|(?::${a}){1,4}|:)| // 1:2:3::          1:2:3::5:6:7:8   1:2:3::8        1:2:3::5:6:7:1.2.3.4
(?:${a}:){2}(?:(?::${a}){0,3}:${r}|(?::${a}){1,5}|:)| // 1:2::            1:2::4:5:6:7:8   1:2::8          1:2::4:5:6:7:1.2.3.4
(?:${a}:){1}(?:(?::${a}){0,4}:${r}|(?::${a}){1,6}|:)| // 1::              1::3:4:5:6:7:8   1::8            1::3:4:5:6:7:1.2.3.4
(?::(?:(?::${a}){0,5}:${r}|(?::${a}){1,7}|:))             // ::2:3:4:5:6:7:8  ::2:3:4:5:6:7:8  ::8             ::1.2.3.4
)(?:%[0-9a-zA-Z]{1,})?                                             // %eth0            %1
`
      .replace(/\s*\/\/.*$/gm, "")
      .replace(/\n/g, "")
      .trim(),
    o = new RegExp(`(?:^${r}$)|(?:^${m}$)`),
    i = new RegExp(`^${r}$`),
    n = new RegExp(`^${m}$`),
    v = (c) =>
      c && c.exact
        ? o
        : new RegExp(`(?:${t(c)}${r}${t(c)})|(?:${t(c)}${m}${t(c)})`, "g");
  return (
    (v.v4 = (c) => (c && c.exact ? i : new RegExp(`${t(c)}${r}${t(c)}`, "g"))),
    (v.v6 = (c) => (c && c.exact ? n : new RegExp(`${t(c)}${m}${t(c)}`, "g"))),
    (lr = v),
    lr
  );
}
const pa = JSON.parse(
    '["aaa","aarp","abb","abbott","abbvie","abc","able","abogado","abudhabi","ac","academy","accenture","accountant","accountants","aco","actor","ad","ads","adult","ae","aeg","aero","aetna","af","afl","africa","ag","agakhan","agency","ai","aig","airbus","airforce","airtel","akdn","al","alibaba","alipay","allfinanz","allstate","ally","alsace","alstom","am","amazon","americanexpress","americanfamily","amex","amfam","amica","amsterdam","analytics","android","anquan","anz","ao","aol","apartments","app","apple","aq","aquarelle","ar","arab","aramco","archi","army","arpa","art","arte","as","asda","asia","associates","at","athleta","attorney","au","auction","audi","audible","audio","auspost","author","auto","autos","aw","aws","ax","axa","az","azure","ba","baby","baidu","banamex","band","bank","bar","barcelona","barclaycard","barclays","barefoot","bargains","baseball","basketball","bauhaus","bayern","bb","bbc","bbt","bbva","bcg","bcn","bd","be","beats","beauty","beer","bentley","berlin","best","bestbuy","bet","bf","bg","bh","bharti","bi","bible","bid","bike","bing","bingo","bio","biz","bj","black","blackfriday","blockbuster","blog","bloomberg","blue","bm","bms","bmw","bn","bnpparibas","bo","boats","boehringer","bofa","bom","bond","boo","book","booking","bosch","bostik","boston","bot","boutique","box","br","bradesco","bridgestone","broadway","broker","brother","brussels","bs","bt","build","builders","business","buy","buzz","bv","bw","by","bz","bzh","ca","cab","cafe","cal","call","calvinklein","cam","camera","camp","canon","capetown","capital","capitalone","car","caravan","cards","care","career","careers","cars","casa","case","cash","casino","cat","catering","catholic","cba","cbn","cbre","cc","cd","center","ceo","cern","cf","cfa","cfd","cg","ch","chanel","channel","charity","chase","chat","cheap","chintai","christmas","chrome","church","ci","cipriani","circle","cisco","citadel","citi","citic","city","ck","cl","claims","cleaning","click","clinic","clinique","clothing","cloud","club","clubmed","cm","cn","co","coach","codes","coffee","college","cologne","com","commbank","community","company","compare","computer","comsec","condos","construction","consulting","contact","contractors","cooking","cool","coop","corsica","country","coupon","coupons","courses","cpa","cr","credit","creditcard","creditunion","cricket","crown","crs","cruise","cruises","cu","cuisinella","cv","cw","cx","cy","cymru","cyou","cz","dad","dance","data","date","dating","datsun","day","dclk","dds","de","deal","dealer","deals","degree","delivery","dell","deloitte","delta","democrat","dental","dentist","desi","design","dev","dhl","diamonds","diet","digital","direct","directory","discount","discover","dish","diy","dj","dk","dm","dnp","do","docs","doctor","dog","domains","dot","download","drive","dtv","dubai","dunlop","dupont","durban","dvag","dvr","dz","earth","eat","ec","eco","edeka","edu","education","ee","eg","email","emerck","energy","engineer","engineering","enterprises","epson","equipment","er","ericsson","erni","es","esq","estate","et","eu","eurovision","eus","events","exchange","expert","exposed","express","extraspace","fage","fail","fairwinds","faith","family","fan","fans","farm","farmers","fashion","fast","fedex","feedback","ferrari","ferrero","fi","fidelity","fido","film","final","finance","financial","fire","firestone","firmdale","fish","fishing","fit","fitness","fj","fk","flickr","flights","flir","florist","flowers","fly","fm","fo","foo","food","football","ford","forex","forsale","forum","foundation","fox","fr","free","fresenius","frl","frogans","frontier","ftr","fujitsu","fun","fund","furniture","futbol","fyi","ga","gal","gallery","gallo","gallup","game","games","gap","garden","gay","gb","gbiz","gd","gdn","ge","gea","gent","genting","george","gf","gg","ggee","gh","gi","gift","gifts","gives","giving","gl","glass","gle","global","globo","gm","gmail","gmbh","gmo","gmx","gn","godaddy","gold","goldpoint","golf","goo","goodyear","goog","google","gop","got","gov","gp","gq","gr","grainger","graphics","gratis","green","gripe","grocery","group","gs","gt","gu","gucci","guge","guide","guitars","guru","gw","gy","hair","hamburg","hangout","haus","hbo","hdfc","hdfcbank","health","healthcare","help","helsinki","here","hermes","hiphop","hisamitsu","hitachi","hiv","hk","hkt","hm","hn","hockey","holdings","holiday","homedepot","homegoods","homes","homesense","honda","horse","hospital","host","hosting","hot","hotels","hotmail","house","how","hr","hsbc","ht","hu","hughes","hyatt","hyundai","ibm","icbc","ice","icu","id","ie","ieee","ifm","ikano","il","im","imamat","imdb","immo","immobilien","in","inc","industries","infiniti","info","ing","ink","institute","insurance","insure","int","international","intuit","investments","io","ipiranga","iq","ir","irish","is","ismaili","ist","istanbul","it","itau","itv","jaguar","java","jcb","je","jeep","jetzt","jewelry","jio","jll","jm","jmp","jnj","jo","jobs","joburg","jot","joy","jp","jpmorgan","jprs","juegos","juniper","kaufen","kddi","ke","kerryhotels","kerrylogistics","kerryproperties","kfh","kg","kh","ki","kia","kids","kim","kindle","kitchen","kiwi","km","kn","koeln","komatsu","kosher","kp","kpmg","kpn","kr","krd","kred","kuokgroup","kw","ky","kyoto","kz","la","lacaixa","lamborghini","lamer","lancaster","land","landrover","lanxess","lasalle","lat","latino","latrobe","law","lawyer","lb","lc","lds","lease","leclerc","lefrak","legal","lego","lexus","lgbt","li","lidl","life","lifeinsurance","lifestyle","lighting","like","lilly","limited","limo","lincoln","link","lipsy","live","living","lk","llc","llp","loan","loans","locker","locus","lol","london","lotte","lotto","love","lpl","lplfinancial","lr","ls","lt","ltd","ltda","lu","lundbeck","luxe","luxury","lv","ly","ma","madrid","maif","maison","makeup","man","management","mango","map","market","marketing","markets","marriott","marshalls","mattel","mba","mc","mckinsey","md","me","med","media","meet","melbourne","meme","memorial","men","menu","merckmsd","mg","mh","miami","microsoft","mil","mini","mint","mit","mitsubishi","mk","ml","mlb","mls","mm","mma","mn","mo","mobi","mobile","moda","moe","moi","mom","monash","money","monster","mormon","mortgage","moscow","moto","motorcycles","mov","movie","mp","mq","mr","ms","msd","mt","mtn","mtr","mu","museum","music","mv","mw","mx","my","mz","na","nab","nagoya","name","navy","nba","nc","ne","nec","net","netbank","netflix","network","neustar","new","news","next","nextdirect","nexus","nf","nfl","ng","ngo","nhk","ni","nico","nike","nikon","ninja","nissan","nissay","nl","no","nokia","norton","now","nowruz","nowtv","np","nr","nra","nrw","ntt","nu","nyc","nz","obi","observer","office","okinawa","olayan","olayangroup","ollo","om","omega","one","ong","onl","online","ooo","open","oracle","orange","org","organic","origins","osaka","otsuka","ott","ovh","pa","page","panasonic","paris","pars","partners","parts","party","pay","pccw","pe","pet","pf","pfizer","pg","ph","pharmacy","phd","philips","phone","photo","photography","photos","physio","pics","pictet","pictures","pid","pin","ping","pink","pioneer","pizza","pk","pl","place","play","playstation","plumbing","plus","pm","pn","pnc","pohl","poker","politie","porn","post","pr","pramerica","praxi","press","prime","pro","prod","productions","prof","progressive","promo","properties","property","protection","pru","prudential","ps","pt","pub","pw","pwc","py","qa","qpon","quebec","quest","racing","radio","re","read","realestate","realtor","realty","recipes","red","redstone","redumbrella","rehab","reise","reisen","reit","reliance","ren","rent","rentals","repair","report","republican","rest","restaurant","review","reviews","rexroth","rich","richardli","ricoh","ril","rio","rip","ro","rocks","rodeo","rogers","room","rs","rsvp","ru","rugby","ruhr","run","rw","rwe","ryukyu","sa","saarland","safe","safety","sakura","sale","salon","samsclub","samsung","sandvik","sandvikcoromant","sanofi","sap","sarl","sas","save","saxo","sb","sbi","sbs","sc","scb","schaeffler","schmidt","scholarships","school","schule","schwarz","science","scot","sd","se","search","seat","secure","security","seek","select","sener","services","seven","sew","sex","sexy","sfr","sg","sh","shangrila","sharp","shell","shia","shiksha","shoes","shop","shopping","shouji","show","si","silk","sina","singles","site","sj","sk","ski","skin","sky","skype","sl","sling","sm","smart","smile","sn","sncf","so","soccer","social","softbank","software","sohu","solar","solutions","song","sony","soy","spa","space","sport","spot","sr","srl","ss","st","stada","staples","star","statebank","statefarm","stc","stcgroup","stockholm","storage","store","stream","studio","study","style","su","sucks","supplies","supply","support","surf","surgery","suzuki","sv","swatch","swiss","sx","sy","sydney","systems","sz","tab","taipei","talk","taobao","target","tatamotors","tatar","tattoo","tax","taxi","tc","tci","td","tdk","team","tech","technology","tel","temasek","tennis","teva","tf","tg","th","thd","theater","theatre","tiaa","tickets","tienda","tips","tires","tirol","tj","tjmaxx","tjx","tk","tkmaxx","tl","tm","tmall","tn","to","today","tokyo","tools","top","toray","toshiba","total","tours","town","toyota","toys","tr","trade","trading","training","travel","travelers","travelersinsurance","trust","trv","tt","tube","tui","tunes","tushu","tv","tvs","tw","tz","ua","ubank","ubs","ug","uk","unicom","university","uno","uol","ups","us","uy","uz","va","vacations","vana","vanguard","vc","ve","vegas","ventures","verisign","vermögensberater","vermögensberatung","versicherung","vet","vg","vi","viajes","video","vig","viking","villas","vin","vip","virgin","visa","vision","viva","vivo","vlaanderen","vn","vodka","volvo","vote","voting","voto","voyage","vu","wales","walmart","walter","wang","wanggou","watch","watches","weather","weatherchannel","webcam","weber","website","wed","wedding","weibo","weir","wf","whoswho","wien","wiki","williamhill","win","windows","wine","winners","wme","wolterskluwer","woodside","work","works","world","wow","ws","wtc","wtf","xbox","xerox","xihuan","xin","xxx","xyz","yachts","yahoo","yamaxun","yandex","ye","yodobashi","yoga","yokohama","you","youtube","yt","yun","za","zappos","zara","zero","zip","zm","zone","zuerich","zw","ελ","ευ","бг","бел","дети","ею","католик","ком","мкд","мон","москва","онлайн","орг","рус","рф","сайт","срб","укр","қаз","հայ","ישראל","קום","ابوظبي","ارامكو","الاردن","البحرين","الجزائر","السعودية","العليان","المغرب","امارات","ایران","بارت","بازار","بيتك","بھارت","تونس","سودان","سورية","شبكة","عراق","عرب","عمان","فلسطين","قطر","كاثوليك","كوم","مصر","مليسيا","موريتانيا","موقع","همراه","پاکستان","ڀارت","कॉम","नेट","भारत","भारतम्","भारोत","संगठन","বাংলা","ভারত","ভাৰত","ਭਾਰਤ","ભારત","ଭାରତ","இந்தியா","இலங்கை","சிங்கப்பூர்","భారత్","ಭಾರತ","ഭാരതം","ලංකා","คอม","ไทย","ລາວ","გე","みんな","アマゾン","クラウド","グーグル","コム","ストア","セール","ファッション","ポイント","世界","中信","中国","中國","中文网","亚马逊","企业","佛山","信息","健康","八卦","公司","公益","台湾","台灣","商城","商店","商标","嘉里","嘉里大酒店","在线","大拿","天主教","娱乐","家電","广东","微博","慈善","我爱你","手机","招聘","政务","政府","新加坡","新闻","时尚","書籍","机构","淡马锡","游戏","澳門","点看","移动","组织机构","网址","网店","网站","网络","联通","谷歌","购物","通販","集团","電訊盈科","飞利浦","食品","餐厅","香格里拉","香港","닷넷","닷컴","삼성","한국"]',
  ),
  ya = {},
  da = Object.freeze(
    Object.defineProperty(
      { __proto__: null, default: ya },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  bo = ua(da);
var fr, Xt;
function ha() {
  if (Xt) return fr;
  Xt = 1;
  const e = ca(),
    t = pa,
    r = e.v4().source,
    a = e.v6().source,
    m = "(?:(?:[a-z\\u00a1-\\uffff0-9][-_]*)*[a-z\\u00a1-\\uffff0-9]+)",
    o = "(?:\\.(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)*",
    i = "(?:[a-z\\u00a1-\\uffff]{2,})",
    n = `(?:${t.sort((h, g) => g.length - h.length).join("|")})`,
    v = "(?::\\d{2,5})?";
  let c, u;
  return (
    (fr = (h) => {
      h = {
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
        ...h,
      };
      const g =
          h.re2 && u !== !1
            ? (() => {
                if (typeof c == "function") return c;
                try {
                  return ((c = bo), typeof c == "function" ? c : RegExp);
                } catch {
                  return ((u = !1), RegExp);
                }
              })()
            : RegExp,
        p = `(?:(?:[a-z]+:)?//)${h.strict ? "" : "?"}`,
        b = h.auth ? "(?:\\S+(?::\\S*)?@)?" : "",
        E = `(?:\\.${h.strict ? i : h.tlds ? `(?:${h.tlds.sort((w, S) => S.length - w.length).join("|")})` : n})${h.trailingPeriod ? "\\.?" : ""}`;
      let l = '\\s"';
      (h.parens || (l += "\\)"), h.apostrophes || (l += "'"));
      const d = h.trailingPeriod
        ? `(?:[/?#][^${l}]*)?`
        : `(?:(?:[/?#][^${l}]*[^${l}.?!])|[/])?`;
      let s = `(?:${p}|www\\.)${b}(?:`;
      return (
        h.localhost && (s += "localhost|"),
        h.ipv4 && (s += `${r}|`),
        h.ipv6 && (s += `${a}|`),
        (s += `${m}${o}${E})${v}${d}`),
        h.returnString ? s : h.exact ? new g(`(?:^${s}$)`, "i") : new g(s, "ig")
      );
    }),
    fr
  );
}
var ma = ha();
const va = Ve(ma),
  ga = "4.3.209",
  ba = { version: ga },
  Aa =
    "https://22069267152d0556896061c5c67463fc@o248881.ingest.us.sentry.io/4510439832551424",
  Sa = (e) =>
    e
      .replace(/^\([^)]*\): \w+: /, "")
      .replace(/^\w+ failed: /, "")
      .replace(/^COM\.BEEPER\.[A-Z_]+(?: \(HTTP \d+\))?: /, ""),
  en = /^(\w+) failed: /,
  Ea = /^\(([^)]*)\): /,
  wa = /\b((?:M_|COM\.BEEPER\.|FI\.MAU\.|NET\.MAUNIUM\.)[A-Z0-9_.]+)/,
  Ao = (e) =>
    e
      .replace(/[!#][^\s:]+:[^\s,)]+/g, "<roomid>")
      .replace(/@[^\s:]+:[^\s,)]+/g, "<userid>")
      .replace(/\$[A-Za-z0-9_-]{8,}(?::[^\s,)]+)?/g, "<eventid>"),
  Pa = (e) =>
    Ao(Sa(e))
      .replace(/\b[0-9a-f]{8,}\b/gi, "<hex>")
      .replace(/(?<!HTTP )\b\d+\b/g, "<n>")
      .trim()
      .slice(0, 120),
  Oa = (e) => {
    if (e.name !== "RelayedError") return { inner: e };
    const t = e.tag || Ea.exec(e.message ?? "")?.[1],
      r = e.cause;
    return {
      tag: t && t !== "?" ? t : void 0,
      inner: r && typeof r == "object" ? r : e,
    };
  },
  Ra = (e) => {
    const t = e;
    if (!t || typeof t != "object") return;
    const { tag: r, inner: a } = Oa(t),
      m = typeof a.message == "string" ? a.message : "",
      o =
        a.name === "SDKError" ||
        typeof a.internalError == "string" ||
        en.test(m);
    if (!o && !r) return;
    const i =
        a.methodName || en.exec(m)?.[1] || (o ? "unknown" : a.name || "Error"),
      n = wa.exec(`${a.internalError ?? ""}
${m}`)?.[1];
    return { tag: r, method: i, cause: n ?? Pa(m) };
  };
var _a = { userConf: {} };
const wt = _a.userConf;
wt.hw_acceleration;
const Vs = !1;
var ur, rn;
function Ia() {
  if (rn) return ur;
  rn = 1;
  function e(m) {
    if (typeof m != "string")
      throw new TypeError(
        "Path must be a string. Received " + JSON.stringify(m),
      );
  }
  function t(m, o) {
    for (var i = "", n = 0, v = -1, c = 0, u, h = 0; h <= m.length; ++h) {
      if (h < m.length) u = m.charCodeAt(h);
      else {
        if (u === 47) break;
        u = 47;
      }
      if (u === 47) {
        if (!(v === h - 1 || c === 1))
          if (v !== h - 1 && c === 2) {
            if (
              i.length < 2 ||
              n !== 2 ||
              i.charCodeAt(i.length - 1) !== 46 ||
              i.charCodeAt(i.length - 2) !== 46
            ) {
              if (i.length > 2) {
                var g = i.lastIndexOf("/");
                if (g !== i.length - 1) {
                  (g === -1
                    ? ((i = ""), (n = 0))
                    : ((i = i.slice(0, g)),
                      (n = i.length - 1 - i.lastIndexOf("/"))),
                    (v = h),
                    (c = 0));
                  continue;
                }
              } else if (i.length === 2 || i.length === 1) {
                ((i = ""), (n = 0), (v = h), (c = 0));
                continue;
              }
            }
            o && (i.length > 0 ? (i += "/..") : (i = ".."), (n = 2));
          } else
            (i.length > 0
              ? (i += "/" + m.slice(v + 1, h))
              : (i = m.slice(v + 1, h)),
              (n = h - v - 1));
        ((v = h), (c = 0));
      } else u === 46 && c !== -1 ? ++c : (c = -1);
    }
    return i;
  }
  function r(m, o) {
    var i = o.dir || o.root,
      n = o.base || (o.name || "") + (o.ext || "");
    return i ? (i === o.root ? i + n : i + m + n) : n;
  }
  var a = {
    resolve: function () {
      for (
        var o = "", i = !1, n, v = arguments.length - 1;
        v >= -1 && !i;
        v--
      ) {
        var c;
        (v >= 0
          ? (c = arguments[v])
          : (n === void 0 && (n = na.cwd()), (c = n)),
          e(c),
          c.length !== 0 && ((o = c + "/" + o), (i = c.charCodeAt(0) === 47)));
      }
      return (
        (o = t(o, !i)),
        i ? (o.length > 0 ? "/" + o : "/") : o.length > 0 ? o : "."
      );
    },
    normalize: function (o) {
      if ((e(o), o.length === 0)) return ".";
      var i = o.charCodeAt(0) === 47,
        n = o.charCodeAt(o.length - 1) === 47;
      return (
        (o = t(o, !i)),
        o.length === 0 && !i && (o = "."),
        o.length > 0 && n && (o += "/"),
        i ? "/" + o : o
      );
    },
    isAbsolute: function (o) {
      return (e(o), o.length > 0 && o.charCodeAt(0) === 47);
    },
    join: function () {
      if (arguments.length === 0) return ".";
      for (var o, i = 0; i < arguments.length; ++i) {
        var n = arguments[i];
        (e(n), n.length > 0 && (o === void 0 ? (o = n) : (o += "/" + n)));
      }
      return o === void 0 ? "." : a.normalize(o);
    },
    relative: function (o, i) {
      if (
        (e(o),
        e(i),
        o === i || ((o = a.resolve(o)), (i = a.resolve(i)), o === i))
      )
        return "";
      for (var n = 1; n < o.length && o.charCodeAt(n) === 47; ++n);
      for (
        var v = o.length, c = v - n, u = 1;
        u < i.length && i.charCodeAt(u) === 47;
        ++u
      );
      for (
        var h = i.length, g = h - u, p = c < g ? c : g, b = -1, E = 0;
        E <= p;
        ++E
      ) {
        if (E === p) {
          if (g > p) {
            if (i.charCodeAt(u + E) === 47) return i.slice(u + E + 1);
            if (E === 0) return i.slice(u + E);
          } else
            c > p &&
              (o.charCodeAt(n + E) === 47 ? (b = E) : E === 0 && (b = 0));
          break;
        }
        var l = o.charCodeAt(n + E),
          d = i.charCodeAt(u + E);
        if (l !== d) break;
        l === 47 && (b = E);
      }
      var s = "";
      for (E = n + b + 1; E <= v; ++E)
        (E === v || o.charCodeAt(E) === 47) &&
          (s.length === 0 ? (s += "..") : (s += "/.."));
      return s.length > 0
        ? s + i.slice(u + b)
        : ((u += b), i.charCodeAt(u) === 47 && ++u, i.slice(u));
    },
    _makeLong: function (o) {
      return o;
    },
    dirname: function (o) {
      if ((e(o), o.length === 0)) return ".";
      for (
        var i = o.charCodeAt(0), n = i === 47, v = -1, c = !0, u = o.length - 1;
        u >= 1;
        --u
      )
        if (((i = o.charCodeAt(u)), i === 47)) {
          if (!c) {
            v = u;
            break;
          }
        } else c = !1;
      return v === -1 ? (n ? "/" : ".") : n && v === 1 ? "//" : o.slice(0, v);
    },
    basename: function (o, i) {
      if (i !== void 0 && typeof i != "string")
        throw new TypeError('"ext" argument must be a string');
      e(o);
      var n = 0,
        v = -1,
        c = !0,
        u;
      if (i !== void 0 && i.length > 0 && i.length <= o.length) {
        if (i.length === o.length && i === o) return "";
        var h = i.length - 1,
          g = -1;
        for (u = o.length - 1; u >= 0; --u) {
          var p = o.charCodeAt(u);
          if (p === 47) {
            if (!c) {
              n = u + 1;
              break;
            }
          } else
            (g === -1 && ((c = !1), (g = u + 1)),
              h >= 0 &&
                (p === i.charCodeAt(h)
                  ? --h === -1 && (v = u)
                  : ((h = -1), (v = g))));
        }
        return (n === v ? (v = g) : v === -1 && (v = o.length), o.slice(n, v));
      } else {
        for (u = o.length - 1; u >= 0; --u)
          if (o.charCodeAt(u) === 47) {
            if (!c) {
              n = u + 1;
              break;
            }
          } else v === -1 && ((c = !1), (v = u + 1));
        return v === -1 ? "" : o.slice(n, v);
      }
    },
    extname: function (o) {
      e(o);
      for (
        var i = -1, n = 0, v = -1, c = !0, u = 0, h = o.length - 1;
        h >= 0;
        --h
      ) {
        var g = o.charCodeAt(h);
        if (g === 47) {
          if (!c) {
            n = h + 1;
            break;
          }
          continue;
        }
        (v === -1 && ((c = !1), (v = h + 1)),
          g === 46
            ? i === -1
              ? (i = h)
              : u !== 1 && (u = 1)
            : i !== -1 && (u = -1));
      }
      return i === -1 ||
        v === -1 ||
        u === 0 ||
        (u === 1 && i === v - 1 && i === n + 1)
        ? ""
        : o.slice(i, v);
    },
    format: function (o) {
      if (o === null || typeof o != "object")
        throw new TypeError(
          'The "pathObject" argument must be of type Object. Received type ' +
            typeof o,
        );
      return r("/", o);
    },
    parse: function (o) {
      e(o);
      var i = { root: "", dir: "", base: "", ext: "", name: "" };
      if (o.length === 0) return i;
      var n = o.charCodeAt(0),
        v = n === 47,
        c;
      v ? ((i.root = "/"), (c = 1)) : (c = 0);
      for (
        var u = -1, h = 0, g = -1, p = !0, b = o.length - 1, E = 0;
        b >= c;
        --b
      ) {
        if (((n = o.charCodeAt(b)), n === 47)) {
          if (!p) {
            h = b + 1;
            break;
          }
          continue;
        }
        (g === -1 && ((p = !1), (g = b + 1)),
          n === 46
            ? u === -1
              ? (u = b)
              : E !== 1 && (E = 1)
            : u !== -1 && (E = -1));
      }
      return (
        u === -1 ||
        g === -1 ||
        E === 0 ||
        (E === 1 && u === g - 1 && u === h + 1)
          ? g !== -1 &&
            (h === 0 && v
              ? (i.base = i.name = o.slice(1, g))
              : (i.base = i.name = o.slice(h, g)))
          : (h === 0 && v
              ? ((i.name = o.slice(1, u)), (i.base = o.slice(1, g)))
              : ((i.name = o.slice(h, u)), (i.base = o.slice(h, g))),
            (i.ext = o.slice(u, g))),
        h > 0 ? (i.dir = o.slice(0, h - 1)) : v && (i.dir = "/"),
        i
      );
    },
    sep: "/",
    delimiter: ":",
    win32: null,
    posix: null,
  };
  return ((a.posix = a), (ur = a), ur);
}
var xa = Ia();
const qe = Ve(xa);
var Ue = { exports: {} };
var $a = Ue.exports,
  tn;
function Ta() {
  return (
    tn ||
      ((tn = 1),
      (function (e, t) {
        (function (r) {
          var a = t && !t.nodeType && t,
            m = e && !e.nodeType && e,
            o = typeof Ke == "object" && Ke;
          (o.global === o || o.window === o || o.self === o) && (r = o);
          var i,
            n = 2147483647,
            v = 36,
            c = 1,
            u = 26,
            h = 38,
            g = 700,
            p = 72,
            b = 128,
            E = "-",
            l = /^xn--/,
            d = /[^\x20-\x7E]/,
            s = /[\x2E\u3002\uFF0E\uFF61]/g,
            w = {
              overflow: "Overflow: input needs wider integers to process",
              "not-basic": "Illegal input >= 0x80 (not a basic code point)",
              "invalid-input": "Invalid input",
            },
            S = v - c,
            R = Math.floor,
            O = String.fromCharCode,
            A;
          function T(x) {
            throw new RangeError(w[x]);
          }
          function q(x, F) {
            for (var j = x.length, L = []; j--;) L[j] = F(x[j]);
            return L;
          }
          function C(x, F) {
            var j = x.split("@"),
              L = "";
            (j.length > 1 && ((L = j[0] + "@"), (x = j[1])),
              (x = x.replace(s, ".")));
            var z = x.split("."),
              Q = q(z, F).join(".");
            return L + Q;
          }
          function B(x) {
            for (var F = [], j = 0, L = x.length, z, Q; j < L;)
              ((z = x.charCodeAt(j++)),
                z >= 55296 && z <= 56319 && j < L
                  ? ((Q = x.charCodeAt(j++)),
                    (Q & 64512) == 56320
                      ? F.push(((z & 1023) << 10) + (Q & 1023) + 65536)
                      : (F.push(z), j--))
                  : F.push(z));
            return F;
          }
          function $(x) {
            return q(x, function (F) {
              var j = "";
              return (
                F > 65535 &&
                  ((F -= 65536),
                  (j += O(((F >>> 10) & 1023) | 55296)),
                  (F = 56320 | (F & 1023))),
                (j += O(F)),
                j
              );
            }).join("");
          }
          function Y(x) {
            return x - 48 < 10
              ? x - 22
              : x - 65 < 26
                ? x - 65
                : x - 97 < 26
                  ? x - 97
                  : v;
          }
          function G(x, F) {
            return x + 22 + 75 * (x < 26) - ((F != 0) << 5);
          }
          function te(x, F, j) {
            var L = 0;
            for (
              x = j ? R(x / g) : x >> 1, x += R(x / F);
              x > (S * u) >> 1;
              L += v
            )
              x = R(x / S);
            return R(L + ((S + 1) * x) / (x + h));
          }
          function ae(x) {
            var F = [],
              j = x.length,
              L,
              z = 0,
              Q = b,
              H = p,
              Z,
              ne,
              D,
              P,
              I,
              _,
              N,
              M,
              K;
            for (Z = x.lastIndexOf(E), Z < 0 && (Z = 0), ne = 0; ne < Z; ++ne)
              (x.charCodeAt(ne) >= 128 && T("not-basic"),
                F.push(x.charCodeAt(ne)));
            for (D = Z > 0 ? Z + 1 : 0; D < j;) {
              for (
                P = z, I = 1, _ = v;
                D >= j && T("invalid-input"),
                  (N = Y(x.charCodeAt(D++))),
                  (N >= v || N > R((n - z) / I)) && T("overflow"),
                  (z += N * I),
                  (M = _ <= H ? c : _ >= H + u ? u : _ - H),
                  !(N < M);
                _ += v
              )
                ((K = v - M), I > R(n / K) && T("overflow"), (I *= K));
              ((L = F.length + 1),
                (H = te(z - P, L, P == 0)),
                R(z / L) > n - Q && T("overflow"),
                (Q += R(z / L)),
                (z %= L),
                F.splice(z++, 0, Q));
            }
            return $(F);
          }
          function se(x) {
            var F,
              j,
              L,
              z,
              Q,
              H,
              Z,
              ne,
              D,
              P,
              I,
              _ = [],
              N,
              M,
              K,
              U;
            for (x = B(x), N = x.length, F = b, j = 0, Q = p, H = 0; H < N; ++H)
              ((I = x[H]), I < 128 && _.push(O(I)));
            for (L = z = _.length, z && _.push(E); L < N;) {
              for (Z = n, H = 0; H < N; ++H)
                ((I = x[H]), I >= F && I < Z && (Z = I));
              for (
                M = L + 1,
                  Z - F > R((n - j) / M) && T("overflow"),
                  j += (Z - F) * M,
                  F = Z,
                  H = 0;
                H < N;
                ++H
              )
                if (((I = x[H]), I < F && ++j > n && T("overflow"), I == F)) {
                  for (
                    ne = j, D = v;
                    (P = D <= Q ? c : D >= Q + u ? u : D - Q), !(ne < P);
                    D += v
                  )
                    ((U = ne - P),
                      (K = v - P),
                      _.push(O(G(P + (U % K), 0))),
                      (ne = R(U / K)));
                  (_.push(O(G(ne, 0))), (Q = te(j, M, L == z)), (j = 0), ++L);
                }
              (++j, ++F);
            }
            return _.join("");
          }
          function k(x) {
            return C(x, function (F) {
              return l.test(F) ? ae(F.slice(4).toLowerCase()) : F;
            });
          }
          function ee(x) {
            return C(x, function (F) {
              return d.test(F) ? "xn--" + se(F) : F;
            });
          }
          if (
            ((i = {
              version: "1.4.1",
              ucs2: { decode: B, encode: $ },
              decode: ae,
              encode: se,
              toASCII: ee,
              toUnicode: k,
            }),
            a && m)
          )
            if (e.exports == a) m.exports = i;
            else for (A in i) i.hasOwnProperty(A) && (a[A] = i[A]);
          else r.punycode = i;
        })($a);
      })(Ue, Ue.exports)),
    Ue.exports
  );
}
var Na = Ta();
const Ca = Ve(Na);
var cr, nn;
function Pe() {
  return (nn || ((nn = 1), (cr = TypeError)), cr);
}
var pr, on;
function Je() {
  if (on) return pr;
  on = 1;
  var e = typeof Map == "function" && Map.prototype,
    t =
      Object.getOwnPropertyDescriptor && e
        ? Object.getOwnPropertyDescriptor(Map.prototype, "size")
        : null,
    r = e && t && typeof t.get == "function" ? t.get : null,
    a = e && Map.prototype.forEach,
    m = typeof Set == "function" && Set.prototype,
    o =
      Object.getOwnPropertyDescriptor && m
        ? Object.getOwnPropertyDescriptor(Set.prototype, "size")
        : null,
    i = m && o && typeof o.get == "function" ? o.get : null,
    n = m && Set.prototype.forEach,
    v = typeof WeakMap == "function" && WeakMap.prototype,
    c = v ? WeakMap.prototype.has : null,
    u = typeof WeakSet == "function" && WeakSet.prototype,
    h = u ? WeakSet.prototype.has : null,
    g = typeof WeakRef == "function" && WeakRef.prototype,
    p = g ? WeakRef.prototype.deref : null,
    b = Boolean.prototype.valueOf,
    E = Object.prototype.toString,
    l = Function.prototype.toString,
    d = String.prototype.match,
    s = String.prototype.slice,
    w = String.prototype.replace,
    S = String.prototype.toUpperCase,
    R = String.prototype.toLowerCase,
    O = RegExp.prototype.test,
    A = Array.prototype.concat,
    T = Array.prototype.join,
    q = Array.prototype.slice,
    C = Math.floor,
    B = typeof BigInt == "function" ? BigInt.prototype.valueOf : null,
    $ = Object.getOwnPropertySymbols,
    Y =
      typeof Symbol == "function" && typeof Symbol.iterator == "symbol"
        ? Symbol.prototype.toString
        : null,
    G = typeof Symbol == "function" && typeof Symbol.iterator == "object",
    te =
      typeof Symbol == "function" &&
      Symbol.toStringTag &&
      (typeof Symbol.toStringTag === G || !0)
        ? Symbol.toStringTag
        : null,
    ae = Object.prototype.propertyIsEnumerable,
    se =
      (typeof Reflect == "function"
        ? Reflect.getPrototypeOf
        : Object.getPrototypeOf) ||
      ([].__proto__ === Array.prototype
        ? function (f) {
            return f.__proto__;
          }
        : null);
  function k(f, y) {
    if (
      f === 1 / 0 ||
      f === -1 / 0 ||
      f !== f ||
      (f && f > -1e3 && f < 1e3) ||
      O.call(/e/, y)
    )
      return y;
    var J = /[0-9](?=(?:[0-9]{3})+(?![0-9]))/g;
    if (typeof f == "number") {
      var X = f < 0 ? -C(-f) : C(f);
      if (X !== f) {
        var re = String(X),
          W = s.call(y, re.length + 1);
        return (
          w.call(re, J, "$&_") +
          "." +
          w.call(w.call(W, /([0-9]{3})/g, "$&_"), /_$/, "")
        );
      }
    }
    return w.call(y, J, "$&_");
  }
  var ee = bo,
    x = ee.custom,
    F = M(x) ? x : null,
    j = { __proto__: null, double: '"', single: "'" },
    L = { __proto__: null, double: /(["\\])/g, single: /(['\\])/g };
  pr = function f(y, J, X, re) {
    var W = J || {};
    if (oe(W, "quoteStyle") && !oe(j, W.quoteStyle))
      throw new TypeError('option "quoteStyle" must be "single" or "double"');
    if (
      oe(W, "maxStringLength") &&
      (typeof W.maxStringLength == "number"
        ? W.maxStringLength < 0 && W.maxStringLength !== 1 / 0
        : W.maxStringLength !== null)
    )
      throw new TypeError(
        'option "maxStringLength", if provided, must be a positive integer, Infinity, or `null`',
      );
    var Se = oe(W, "customInspect") ? W.customInspect : !0;
    if (typeof Se != "boolean" && Se !== "symbol")
      throw new TypeError(
        "option \"customInspect\", if provided, must be `true`, `false`, or `'symbol'`",
      );
    if (
      oe(W, "indent") &&
      W.indent !== null &&
      W.indent !== "	" &&
      !(parseInt(W.indent, 10) === W.indent && W.indent > 0)
    )
      throw new TypeError(
        'option "indent" must be "\\t", an integer > 0, or `null`',
      );
    if (oe(W, "numericSeparator") && typeof W.numericSeparator != "boolean")
      throw new TypeError(
        'option "numericSeparator", if provided, must be `true` or `false`',
      );
    var Oe = W.numericSeparator;
    if (typeof y > "u") return "undefined";
    if (y === null) return "null";
    if (typeof y == "boolean") return y ? "true" : "false";
    if (typeof y == "string") return Gt(y, W);
    if (typeof y == "number") {
      if (y === 0) return 1 / 0 / y > 0 ? "0" : "-0";
      var de = String(y);
      return Oe ? k(y, de) : de;
    }
    if (typeof y == "bigint") {
      var Ee = String(y) + "n";
      return Oe ? k(y, Ee) : Ee;
    }
    var rr = typeof W.depth > "u" ? 5 : W.depth;
    if ((typeof X > "u" && (X = 0), X >= rr && rr > 0 && typeof y == "object"))
      return Z(y) ? "[Array]" : "[Object]";
    var Ie = Qo(W, X);
    if (typeof re > "u") re = [];
    else if (fe(re, y) >= 0) return "[Circular]";
    function me(xe, We, Zo) {
      if ((We && ((re = q.call(re)), re.push(We)), Zo)) {
        var Yt = { depth: W.depth };
        return (
          oe(W, "quoteStyle") && (Yt.quoteStyle = W.quoteStyle),
          f(xe, Yt, X + 1, re)
        );
      }
      return f(xe, W, X + 1, re);
    }
    if (typeof y == "function" && !D(y)) {
      var Wt = ue(y),
        zt = Ge(y, me);
      return (
        "[Function" +
        (Wt ? ": " + Wt : " (anonymous)") +
        "]" +
        (zt.length > 0 ? " { " + T.call(zt, ", ") + " }" : "")
      );
    }
    if (M(y)) {
      var Ht = G
        ? w.call(String(y), /^(Symbol\(.*\))_[^)]*$/, "$1")
        : Y.call(y);
      return typeof y == "object" && !G ? ke(Ht) : Ht;
    }
    if (Ko(y)) {
      for (
        var De = "<" + R.call(String(y.nodeName)),
          tr = y.attributes || [],
          Le = 0;
        Le < tr.length;
        Le++
      )
        De += " " + tr[Le].name + "=" + z(Q(tr[Le].value), "double", W);
      return (
        (De += ">"),
        y.childNodes && y.childNodes.length && (De += "..."),
        (De += "</" + R.call(String(y.nodeName)) + ">"),
        De
      );
    }
    if (Z(y)) {
      if (y.length === 0) return "[]";
      var nr = Ge(y, me);
      return Ie && !Jo(nr)
        ? "[" + er(nr, Ie) + "]"
        : "[ " + T.call(nr, ", ") + " ]";
    }
    if (P(y)) {
      var or = Ge(y, me);
      return !("cause" in Error.prototype) &&
        "cause" in y &&
        !ae.call(y, "cause")
        ? "{ [" +
            String(y) +
            "] " +
            T.call(A.call("[cause]: " + me(y.cause), or), ", ") +
            " }"
        : or.length === 0
          ? "[" + String(y) + "]"
          : "{ [" + String(y) + "] " + T.call(or, ", ") + " }";
    }
    if (typeof y == "object" && Se) {
      if (F && typeof y[F] == "function" && ee) return ee(y, { depth: rr - X });
      if (Se !== "symbol" && typeof y.inspect == "function") return y.inspect();
    }
    if (V(y)) {
      var Kt = [];
      return (
        a &&
          a.call(y, function (xe, We) {
            Kt.push(me(We, y, !0) + " => " + me(xe, y));
          }),
        Lt("Map", r.call(y), Kt, Ie)
      );
    }
    if (ye(y)) {
      var Vt = [];
      return (
        n &&
          n.call(y, function (xe) {
            Vt.push(me(xe, y));
          }),
        Lt("Set", i.call(y), Vt, Ie)
      );
    }
    if (ce(y)) return Xe("WeakMap");
    if (Ho(y)) return Xe("WeakSet");
    if (pe(y)) return Xe("WeakRef");
    if (_(y)) return ke(me(Number(y)));
    if (K(y)) return ke(me(B.call(y)));
    if (N(y)) return ke(b.call(y));
    if (I(y)) return ke(me(String(y)));
    if (typeof window < "u" && y === window) return "{ [object Window] }";
    if (
      (typeof globalThis < "u" && y === globalThis) ||
      (typeof Ke < "u" && y === Ke)
    )
      return "{ [object globalThis] }";
    if (!ne(y) && !D(y)) {
      var ar = Ge(y, me),
        Jt = se
          ? se(y) === Object.prototype
          : y instanceof Object || y.constructor === Object,
        ir = y instanceof Object ? "" : "null prototype",
        Qt =
          !Jt && te && Object(y) === y && te in y
            ? s.call(le(y), 8, -1)
            : ir
              ? "Object"
              : "",
        Yo =
          Jt || typeof y.constructor != "function"
            ? ""
            : y.constructor.name
              ? y.constructor.name + " "
              : "",
        sr =
          Yo +
          (Qt || ir
            ? "[" + T.call(A.call([], Qt || [], ir || []), ": ") + "] "
            : "");
      return ar.length === 0
        ? sr + "{}"
        : Ie
          ? sr + "{" + er(ar, Ie) + "}"
          : sr + "{ " + T.call(ar, ", ") + " }";
    }
    return String(y);
  };
  function z(f, y, J) {
    var X = J.quoteStyle || y,
      re = j[X];
    return re + f + re;
  }
  function Q(f) {
    return w.call(String(f), /"/g, "&quot;");
  }
  function H(f) {
    return !te || !(typeof f == "object" && (te in f || typeof f[te] < "u"));
  }
  function Z(f) {
    return le(f) === "[object Array]" && H(f);
  }
  function ne(f) {
    return le(f) === "[object Date]" && H(f);
  }
  function D(f) {
    return le(f) === "[object RegExp]" && H(f);
  }
  function P(f) {
    return le(f) === "[object Error]" && H(f);
  }
  function I(f) {
    return le(f) === "[object String]" && H(f);
  }
  function _(f) {
    return le(f) === "[object Number]" && H(f);
  }
  function N(f) {
    return le(f) === "[object Boolean]" && H(f);
  }
  function M(f) {
    if (G) return f && typeof f == "object" && f instanceof Symbol;
    if (typeof f == "symbol") return !0;
    if (!f || typeof f != "object" || !Y) return !1;
    try {
      return (Y.call(f), !0);
    } catch {}
    return !1;
  }
  function K(f) {
    if (!f || typeof f != "object" || !B) return !1;
    try {
      return (B.call(f), !0);
    } catch {}
    return !1;
  }
  var U =
    Object.prototype.hasOwnProperty ||
    function (f) {
      return f in this;
    };
  function oe(f, y) {
    return U.call(f, y);
  }
  function le(f) {
    return E.call(f);
  }
  function ue(f) {
    if (f.name) return f.name;
    var y = d.call(l.call(f), /^function\s*([\w$]+)/);
    return y ? y[1] : null;
  }
  function fe(f, y) {
    if (f.indexOf) return f.indexOf(y);
    for (var J = 0, X = f.length; J < X; J++) if (f[J] === y) return J;
    return -1;
  }
  function V(f) {
    if (!r || !f || typeof f != "object") return !1;
    try {
      r.call(f);
      try {
        i.call(f);
      } catch {
        return !0;
      }
      return f instanceof Map;
    } catch {}
    return !1;
  }
  function ce(f) {
    if (!c || !f || typeof f != "object") return !1;
    try {
      c.call(f, c);
      try {
        h.call(f, h);
      } catch {
        return !0;
      }
      return f instanceof WeakMap;
    } catch {}
    return !1;
  }
  function pe(f) {
    if (!p || !f || typeof f != "object") return !1;
    try {
      return (p.call(f), !0);
    } catch {}
    return !1;
  }
  function ye(f) {
    if (!i || !f || typeof f != "object") return !1;
    try {
      i.call(f);
      try {
        r.call(f);
      } catch {
        return !0;
      }
      return f instanceof Set;
    } catch {}
    return !1;
  }
  function Ho(f) {
    if (!h || !f || typeof f != "object") return !1;
    try {
      h.call(f, h);
      try {
        c.call(f, c);
      } catch {
        return !0;
      }
      return f instanceof WeakSet;
    } catch {}
    return !1;
  }
  function Ko(f) {
    return !f || typeof f != "object"
      ? !1
      : typeof HTMLElement < "u" && f instanceof HTMLElement
        ? !0
        : typeof f.nodeName == "string" && typeof f.getAttribute == "function";
  }
  function Gt(f, y) {
    if (f.length > y.maxStringLength) {
      var J = f.length - y.maxStringLength,
        X = "... " + J + " more character" + (J > 1 ? "s" : "");
      return Gt(s.call(f, 0, y.maxStringLength), y) + X;
    }
    var re = L[y.quoteStyle || "single"];
    re.lastIndex = 0;
    var W = w.call(w.call(f, re, "\\$1"), /[\x00-\x1f]/g, Vo);
    return z(W, "single", y);
  }
  function Vo(f) {
    var y = f.charCodeAt(0),
      J = { 8: "b", 9: "t", 10: "n", 12: "f", 13: "r" }[y];
    return J ? "\\" + J : "\\x" + (y < 16 ? "0" : "") + S.call(y.toString(16));
  }
  function ke(f) {
    return "Object(" + f + ")";
  }
  function Xe(f) {
    return f + " { ? }";
  }
  function Lt(f, y, J, X) {
    var re = X ? er(J, X) : T.call(J, ", ");
    return f + " (" + y + ") {" + re + "}";
  }
  function Jo(f) {
    for (var y = 0; y < f.length; y++)
      if (
        fe(
          f[y],
          `
`,
        ) >= 0
      )
        return !1;
    return !0;
  }
  function Qo(f, y) {
    var J;
    if (f.indent === "	") J = "	";
    else if (typeof f.indent == "number" && f.indent > 0)
      J = T.call(Array(f.indent + 1), " ");
    else return null;
    return { base: J, prev: T.call(Array(y + 1), J) };
  }
  function er(f, y) {
    if (f.length === 0) return "";
    var J =
      `
` +
      y.prev +
      y.base;
    return (
      J +
      T.call(f, "," + J) +
      `
` +
      y.prev
    );
  }
  function Ge(f, y) {
    var J = Z(f),
      X = [];
    if (J) {
      X.length = f.length;
      for (var re = 0; re < f.length; re++)
        X[re] = oe(f, re) ? y(f[re], f) : "";
    }
    var W = typeof $ == "function" ? $(f) : [],
      Se;
    if (G) {
      Se = {};
      for (var Oe = 0; Oe < W.length; Oe++) Se["$" + W[Oe]] = W[Oe];
    }
    for (var de in f)
      oe(f, de) &&
        ((J && String(Number(de)) === de && de < f.length) ||
          (G && Se["$" + de] instanceof Symbol) ||
          (O.call(/[^\w$]/, de)
            ? X.push(y(de, f) + ": " + y(f[de], f))
            : X.push(de + ": " + y(f[de], f))));
    if (typeof $ == "function")
      for (var Ee = 0; Ee < W.length; Ee++)
        ae.call(f, W[Ee]) && X.push("[" + y(W[Ee]) + "]: " + y(f[W[Ee]], f));
    return X;
  }
  return pr;
}
var yr, an;
function Fa() {
  if (an) return yr;
  an = 1;
  var e = Je(),
    t = Pe(),
    r = function (n, v, c) {
      for (var u = n, h; (h = u.next) != null; u = h)
        if (h.key === v)
          return ((u.next = h.next), c || ((h.next = n.next), (n.next = h)), h);
    },
    a = function (n, v) {
      if (n) {
        var c = r(n, v);
        return c && c.value;
      }
    },
    m = function (n, v, c) {
      var u = r(n, v);
      u ? (u.value = c) : (n.next = { key: v, next: n.next, value: c });
    },
    o = function (n, v) {
      return n ? !!r(n, v) : !1;
    },
    i = function (n, v) {
      if (n) return r(n, v, !0);
    };
  return (
    (yr = function () {
      var v,
        c = {
          assert: function (u) {
            if (!c.has(u)) throw new t("Side channel does not contain " + e(u));
          },
          delete: function (u) {
            var h = v && v.next,
              g = i(v, u);
            return (g && h && h === g && (v = void 0), !!g);
          },
          get: function (u) {
            return a(v, u);
          },
          has: function (u) {
            return o(v, u);
          },
          set: function (u, h) {
            (v || (v = { next: void 0 }), m(v, u, h));
          },
        };
      return c;
    }),
    yr
  );
}
var dr, sn;
function ka() {
  return (sn || ((sn = 1), (dr = Object)), dr);
}
var hr, ln;
function Pt() {
  return (ln || ((ln = 1), (hr = Error)), hr);
}
var mr, fn;
function Ot() {
  return (fn || ((fn = 1), (mr = EvalError)), mr);
}
var vr, un;
function Rt() {
  return (un || ((un = 1), (vr = RangeError)), vr);
}
var gr, cn;
function _t() {
  return (cn || ((cn = 1), (gr = ReferenceError)), gr);
}
var br, pn;
function It() {
  return (pn || ((pn = 1), (br = SyntaxError)), br);
}
var Ar, yn;
function xt() {
  return (yn || ((yn = 1), (Ar = URIError)), Ar);
}
var Sr, dn;
function $t() {
  return (dn || ((dn = 1), (Sr = Math.abs)), Sr);
}
var Er, hn;
function Tt() {
  return (hn || ((hn = 1), (Er = Math.floor)), Er);
}
var wr, mn;
function Nt() {
  return (mn || ((mn = 1), (wr = Math.max)), wr);
}
var Pr, vn;
function Ct() {
  return (vn || ((vn = 1), (Pr = Math.min)), Pr);
}
var Or, gn;
function Ft() {
  return (gn || ((gn = 1), (Or = Math.pow)), Or);
}
var Rr, bn;
function kt() {
  return (bn || ((bn = 1), (Rr = Math.round)), Rr);
}
var _r, An;
function Da() {
  return (
    An ||
      ((An = 1),
      (_r =
        Number.isNaN ||
        function (t) {
          return t !== t;
        })),
    _r
  );
}
var Ir, Sn;
function Dt() {
  if (Sn) return Ir;
  Sn = 1;
  var e = Da();
  return (
    (Ir = function (r) {
      return e(r) || r === 0 ? r : r < 0 ? -1 : 1;
    }),
    Ir
  );
}
var xr, En;
function Ua() {
  return (En || ((En = 1), (xr = Object.getOwnPropertyDescriptor)), xr);
}
var $r, wn;
function qa() {
  if (wn) return $r;
  wn = 1;
  var e = Ua();
  if (e)
    try {
      e([], "length");
    } catch {
      e = null;
    }
  return (($r = e), $r);
}
var Tr, Pn;
function Ut() {
  if (Pn) return Tr;
  Pn = 1;
  var e = Object.defineProperty || !1;
  if (e)
    try {
      e({}, "a", { value: 1 });
    } catch {
      e = !1;
    }
  return ((Tr = e), Tr);
}
var Nr, On;
function Ma() {
  return (
    On ||
      ((On = 1),
      (Nr = function () {
        if (
          typeof Symbol != "function" ||
          typeof Object.getOwnPropertySymbols != "function"
        )
          return !1;
        if (typeof Symbol.iterator == "symbol") return !0;
        var t = {},
          r = Symbol("test"),
          a = Object(r);
        if (
          typeof r == "string" ||
          Object.prototype.toString.call(r) !== "[object Symbol]" ||
          Object.prototype.toString.call(a) !== "[object Symbol]"
        )
          return !1;
        var m = 42;
        t[r] = m;
        for (var o in t) return !1;
        if (
          (typeof Object.keys == "function" && Object.keys(t).length !== 0) ||
          (typeof Object.getOwnPropertyNames == "function" &&
            Object.getOwnPropertyNames(t).length !== 0)
        )
          return !1;
        var i = Object.getOwnPropertySymbols(t);
        if (
          i.length !== 1 ||
          i[0] !== r ||
          !Object.prototype.propertyIsEnumerable.call(t, r)
        )
          return !1;
        if (typeof Object.getOwnPropertyDescriptor == "function") {
          var n = Object.getOwnPropertyDescriptor(t, r);
          if (n.value !== m || n.enumerable !== !0) return !1;
        }
        return !0;
      })),
    Nr
  );
}
var Cr, Rn;
function ja() {
  if (Rn) return Cr;
  Rn = 1;
  var e = typeof Symbol < "u" && Symbol,
    t = Ma();
  return (
    (Cr = function () {
      return typeof e != "function" ||
        typeof Symbol != "function" ||
        typeof e("foo") != "symbol" ||
        typeof Symbol("bar") != "symbol"
        ? !1
        : t();
    }),
    Cr
  );
}
var Fr, _n;
function Qe() {
  return (
    _n ||
      ((_n = 1),
      (Fr = (typeof Reflect < "u" && Reflect.getPrototypeOf) || null)),
    Fr
  );
}
var kr, In;
function Ba() {
  return (In || ((In = 1), (kr = Object)), kr);
}
var Dr, xn;
function Ye() {
  if (xn) return Dr;
  xn = 1;
  var e = Ba();
  return ((Dr = e.getPrototypeOf || null), Dr);
}
var Ur, $n;
function Ga() {
  if ($n) return Ur;
  $n = 1;
  var e = "Function.prototype.bind called on incompatible ",
    t = Object.prototype.toString,
    r = Math.max,
    a = "[object Function]",
    m = function (v, c) {
      for (var u = [], h = 0; h < v.length; h += 1) u[h] = v[h];
      for (var g = 0; g < c.length; g += 1) u[g + v.length] = c[g];
      return u;
    },
    o = function (v, c) {
      for (var u = [], h = c, g = 0; h < v.length; h += 1, g += 1) u[g] = v[h];
      return u;
    },
    i = function (n, v) {
      for (var c = "", u = 0; u < n.length; u += 1)
        ((c += n[u]), u + 1 < n.length && (c += v));
      return c;
    };
  return (
    (Ur = function (v) {
      var c = this;
      if (typeof c != "function" || t.apply(c) !== a)
        throw new TypeError(e + c);
      for (
        var u = o(arguments, 1),
          h,
          g = function () {
            if (this instanceof h) {
              var d = c.apply(this, m(u, arguments));
              return Object(d) === d ? d : this;
            }
            return c.apply(v, m(u, arguments));
          },
          p = r(0, c.length - u.length),
          b = [],
          E = 0;
        E < p;
        E++
      )
        b[E] = "$" + E;
      if (
        ((h = Function(
          "binder",
          "return function (" +
            i(b, ",") +
            "){ return binder.apply(this,arguments); }",
        )(g)),
        c.prototype)
      ) {
        var l = function () {};
        ((l.prototype = c.prototype),
          (h.prototype = new l()),
          (l.prototype = null));
      }
      return h;
    }),
    Ur
  );
}
var qr, Tn;
function Ce() {
  if (Tn) return qr;
  Tn = 1;
  var e = Ga();
  return ((qr = Function.prototype.bind || e), qr);
}
var Mr, Nn;
function je() {
  return (Nn || ((Nn = 1), (Mr = Function.prototype.call)), Mr);
}
var jr, Cn;
function Ze() {
  return (Cn || ((Cn = 1), (jr = Function.prototype.apply)), jr);
}
var Br, Fn;
function La() {
  return (
    Fn || ((Fn = 1), (Br = typeof Reflect < "u" && Reflect && Reflect.apply)),
    Br
  );
}
var Gr, kn;
function Wa() {
  if (kn) return Gr;
  kn = 1;
  var e = Ce(),
    t = Ze(),
    r = je(),
    a = La();
  return ((Gr = a || e.call(r, t)), Gr);
}
var Lr, Dn;
function So() {
  if (Dn) return Lr;
  Dn = 1;
  var e = Ce(),
    t = Pe(),
    r = je(),
    a = Wa();
  return (
    (Lr = function (o) {
      if (o.length < 1 || typeof o[0] != "function")
        throw new t("a function is required");
      return a(e, r, o);
    }),
    Lr
  );
}
var Wr, Un;
function za() {
  return (Un || ((Un = 1), (Wr = Object.getOwnPropertyDescriptor)), Wr);
}
var zr, qn;
function Ha() {
  if (qn) return zr;
  qn = 1;
  var e = za();
  if (e)
    try {
      e([], "length");
    } catch {
      e = null;
    }
  return ((zr = e), zr);
}
var Hr, Mn;
function Ka() {
  if (Mn) return Hr;
  Mn = 1;
  var e = So(),
    t = Ha(),
    r;
  try {
    r = [].__proto__ === Array.prototype;
  } catch (i) {
    if (
      !i ||
      typeof i != "object" ||
      !("code" in i) ||
      i.code !== "ERR_PROTO_ACCESS"
    )
      throw i;
  }
  var a = !!r && t && t(Object.prototype, "__proto__"),
    m = Object,
    o = m.getPrototypeOf;
  return (
    (Hr =
      a && typeof a.get == "function"
        ? e([a.get])
        : typeof o == "function"
          ? function (n) {
              return o(n == null ? n : m(n));
            }
          : !1),
    Hr
  );
}
var Kr, jn;
function qt() {
  if (jn) return Kr;
  jn = 1;
  var e = Qe(),
    t = Ye(),
    r = Ka();
  return (
    (Kr = e
      ? function (m) {
          return e(m);
        }
      : t
        ? function (m) {
            if (!m || (typeof m != "object" && typeof m != "function"))
              throw new TypeError("getProto: not an object");
            return t(m);
          }
        : r
          ? function (m) {
              return r(m);
            }
          : null),
    Kr
  );
}
var Vr, Bn;
function Mt() {
  if (Bn) return Vr;
  Bn = 1;
  var e = Function.prototype.call,
    t = Object.prototype.hasOwnProperty,
    r = Ce();
  return ((Vr = r.call(e, t)), Vr);
}
var Jr, Gn;
function Va() {
  if (Gn) return Jr;
  Gn = 1;
  var e,
    t = ka(),
    r = Pt(),
    a = Ot(),
    m = Rt(),
    o = _t(),
    i = It(),
    n = Pe(),
    v = xt(),
    c = $t(),
    u = Tt(),
    h = Nt(),
    g = Ct(),
    p = Ft(),
    b = kt(),
    E = Dt(),
    l = Function,
    d = function (D) {
      try {
        return l('"use strict"; return (' + D + ").constructor;")();
      } catch {}
    },
    s = qa(),
    w = Ut(),
    S = function () {
      throw new n();
    },
    R = s
      ? (function () {
          try {
            return (arguments.callee, S);
          } catch {
            try {
              return s(arguments, "callee").get;
            } catch {
              return S;
            }
          }
        })()
      : S,
    O = ja()(),
    A = qt(),
    T = Ye(),
    q = Qe(),
    C = Ze(),
    B = je(),
    $ = {},
    Y = typeof Uint8Array > "u" || !A ? e : A(Uint8Array),
    G = {
      __proto__: null,
      "%AggregateError%": typeof AggregateError > "u" ? e : AggregateError,
      "%Array%": Array,
      "%ArrayBuffer%": typeof ArrayBuffer > "u" ? e : ArrayBuffer,
      "%ArrayIteratorPrototype%": O && A ? A([][Symbol.iterator]()) : e,
      "%AsyncFromSyncIteratorPrototype%": e,
      "%AsyncFunction%": $,
      "%AsyncGenerator%": $,
      "%AsyncGeneratorFunction%": $,
      "%AsyncIteratorPrototype%": $,
      "%Atomics%": typeof Atomics > "u" ? e : Atomics,
      "%BigInt%": typeof BigInt > "u" ? e : BigInt,
      "%BigInt64Array%": typeof BigInt64Array > "u" ? e : BigInt64Array,
      "%BigUint64Array%": typeof BigUint64Array > "u" ? e : BigUint64Array,
      "%Boolean%": Boolean,
      "%DataView%": typeof DataView > "u" ? e : DataView,
      "%Date%": Date,
      "%decodeURI%": decodeURI,
      "%decodeURIComponent%": decodeURIComponent,
      "%encodeURI%": encodeURI,
      "%encodeURIComponent%": encodeURIComponent,
      "%Error%": r,
      "%eval%": eval,
      "%EvalError%": a,
      "%Float16Array%": typeof Float16Array > "u" ? e : Float16Array,
      "%Float32Array%": typeof Float32Array > "u" ? e : Float32Array,
      "%Float64Array%": typeof Float64Array > "u" ? e : Float64Array,
      "%FinalizationRegistry%":
        typeof FinalizationRegistry > "u" ? e : FinalizationRegistry,
      "%Function%": l,
      "%GeneratorFunction%": $,
      "%Int8Array%": typeof Int8Array > "u" ? e : Int8Array,
      "%Int16Array%": typeof Int16Array > "u" ? e : Int16Array,
      "%Int32Array%": typeof Int32Array > "u" ? e : Int32Array,
      "%isFinite%": isFinite,
      "%isNaN%": isNaN,
      "%IteratorPrototype%": O && A ? A(A([][Symbol.iterator]())) : e,
      "%JSON%": typeof JSON == "object" ? JSON : e,
      "%Map%": typeof Map > "u" ? e : Map,
      "%MapIteratorPrototype%":
        typeof Map > "u" || !O || !A ? e : A(new Map()[Symbol.iterator]()),
      "%Math%": Math,
      "%Number%": Number,
      "%Object%": t,
      "%Object.getOwnPropertyDescriptor%": s,
      "%parseFloat%": parseFloat,
      "%parseInt%": parseInt,
      "%Promise%": typeof Promise > "u" ? e : Promise,
      "%Proxy%": typeof Proxy > "u" ? e : Proxy,
      "%RangeError%": m,
      "%ReferenceError%": o,
      "%Reflect%": typeof Reflect > "u" ? e : Reflect,
      "%RegExp%": RegExp,
      "%Set%": typeof Set > "u" ? e : Set,
      "%SetIteratorPrototype%":
        typeof Set > "u" || !O || !A ? e : A(new Set()[Symbol.iterator]()),
      "%SharedArrayBuffer%":
        typeof SharedArrayBuffer > "u" ? e : SharedArrayBuffer,
      "%String%": String,
      "%StringIteratorPrototype%": O && A ? A(""[Symbol.iterator]()) : e,
      "%Symbol%": O ? Symbol : e,
      "%SyntaxError%": i,
      "%ThrowTypeError%": R,
      "%TypedArray%": Y,
      "%TypeError%": n,
      "%Uint8Array%": typeof Uint8Array > "u" ? e : Uint8Array,
      "%Uint8ClampedArray%":
        typeof Uint8ClampedArray > "u" ? e : Uint8ClampedArray,
      "%Uint16Array%": typeof Uint16Array > "u" ? e : Uint16Array,
      "%Uint32Array%": typeof Uint32Array > "u" ? e : Uint32Array,
      "%URIError%": v,
      "%WeakMap%": typeof WeakMap > "u" ? e : WeakMap,
      "%WeakRef%": typeof WeakRef > "u" ? e : WeakRef,
      "%WeakSet%": typeof WeakSet > "u" ? e : WeakSet,
      "%Function.prototype.call%": B,
      "%Function.prototype.apply%": C,
      "%Object.defineProperty%": w,
      "%Object.getPrototypeOf%": T,
      "%Math.abs%": c,
      "%Math.floor%": u,
      "%Math.max%": h,
      "%Math.min%": g,
      "%Math.pow%": p,
      "%Math.round%": b,
      "%Math.sign%": E,
      "%Reflect.getPrototypeOf%": q,
    };
  if (A)
    try {
      null.error;
    } catch (D) {
      var te = A(A(D));
      G["%Error.prototype%"] = te;
    }
  var ae = function D(P) {
      var I;
      if (P === "%AsyncFunction%") I = d("async function () {}");
      else if (P === "%GeneratorFunction%") I = d("function* () {}");
      else if (P === "%AsyncGeneratorFunction%") I = d("async function* () {}");
      else if (P === "%AsyncGenerator%") {
        var _ = D("%AsyncGeneratorFunction%");
        _ && (I = _.prototype);
      } else if (P === "%AsyncIteratorPrototype%") {
        var N = D("%AsyncGenerator%");
        N && A && (I = A(N.prototype));
      }
      return ((G[P] = I), I);
    },
    se = {
      __proto__: null,
      "%ArrayBufferPrototype%": ["ArrayBuffer", "prototype"],
      "%ArrayPrototype%": ["Array", "prototype"],
      "%ArrayProto_entries%": ["Array", "prototype", "entries"],
      "%ArrayProto_forEach%": ["Array", "prototype", "forEach"],
      "%ArrayProto_keys%": ["Array", "prototype", "keys"],
      "%ArrayProto_values%": ["Array", "prototype", "values"],
      "%AsyncFunctionPrototype%": ["AsyncFunction", "prototype"],
      "%AsyncGenerator%": ["AsyncGeneratorFunction", "prototype"],
      "%AsyncGeneratorPrototype%": [
        "AsyncGeneratorFunction",
        "prototype",
        "prototype",
      ],
      "%BooleanPrototype%": ["Boolean", "prototype"],
      "%DataViewPrototype%": ["DataView", "prototype"],
      "%DatePrototype%": ["Date", "prototype"],
      "%ErrorPrototype%": ["Error", "prototype"],
      "%EvalErrorPrototype%": ["EvalError", "prototype"],
      "%Float32ArrayPrototype%": ["Float32Array", "prototype"],
      "%Float64ArrayPrototype%": ["Float64Array", "prototype"],
      "%FunctionPrototype%": ["Function", "prototype"],
      "%Generator%": ["GeneratorFunction", "prototype"],
      "%GeneratorPrototype%": ["GeneratorFunction", "prototype", "prototype"],
      "%Int8ArrayPrototype%": ["Int8Array", "prototype"],
      "%Int16ArrayPrototype%": ["Int16Array", "prototype"],
      "%Int32ArrayPrototype%": ["Int32Array", "prototype"],
      "%JSONParse%": ["JSON", "parse"],
      "%JSONStringify%": ["JSON", "stringify"],
      "%MapPrototype%": ["Map", "prototype"],
      "%NumberPrototype%": ["Number", "prototype"],
      "%ObjectPrototype%": ["Object", "prototype"],
      "%ObjProto_toString%": ["Object", "prototype", "toString"],
      "%ObjProto_valueOf%": ["Object", "prototype", "valueOf"],
      "%PromisePrototype%": ["Promise", "prototype"],
      "%PromiseProto_then%": ["Promise", "prototype", "then"],
      "%Promise_all%": ["Promise", "all"],
      "%Promise_reject%": ["Promise", "reject"],
      "%Promise_resolve%": ["Promise", "resolve"],
      "%RangeErrorPrototype%": ["RangeError", "prototype"],
      "%ReferenceErrorPrototype%": ["ReferenceError", "prototype"],
      "%RegExpPrototype%": ["RegExp", "prototype"],
      "%SetPrototype%": ["Set", "prototype"],
      "%SharedArrayBufferPrototype%": ["SharedArrayBuffer", "prototype"],
      "%StringPrototype%": ["String", "prototype"],
      "%SymbolPrototype%": ["Symbol", "prototype"],
      "%SyntaxErrorPrototype%": ["SyntaxError", "prototype"],
      "%TypedArrayPrototype%": ["TypedArray", "prototype"],
      "%TypeErrorPrototype%": ["TypeError", "prototype"],
      "%Uint8ArrayPrototype%": ["Uint8Array", "prototype"],
      "%Uint8ClampedArrayPrototype%": ["Uint8ClampedArray", "prototype"],
      "%Uint16ArrayPrototype%": ["Uint16Array", "prototype"],
      "%Uint32ArrayPrototype%": ["Uint32Array", "prototype"],
      "%URIErrorPrototype%": ["URIError", "prototype"],
      "%WeakMapPrototype%": ["WeakMap", "prototype"],
      "%WeakSetPrototype%": ["WeakSet", "prototype"],
    },
    k = Ce(),
    ee = Mt(),
    x = k.call(B, Array.prototype.concat),
    F = k.call(C, Array.prototype.splice),
    j = k.call(B, String.prototype.replace),
    L = k.call(B, String.prototype.slice),
    z = k.call(B, RegExp.prototype.exec),
    Q =
      /[^%.[\]]+|\[(?:(-?\d+(?:\.\d+)?)|(["'])((?:(?!\2)[^\\]|\\.)*?)\2)\]|(?=(?:\.|\[\])(?:\.|\[\]|%$))/g,
    H = /\\(\\)?/g,
    Z = function (P) {
      var I = L(P, 0, 1),
        _ = L(P, -1);
      if (I === "%" && _ !== "%")
        throw new i("invalid intrinsic syntax, expected closing `%`");
      if (_ === "%" && I !== "%")
        throw new i("invalid intrinsic syntax, expected opening `%`");
      var N = [];
      return (
        j(P, Q, function (M, K, U, oe) {
          N[N.length] = U ? j(oe, H, "$1") : K || M;
        }),
        N
      );
    },
    ne = function (P, I) {
      var _ = P,
        N;
      if ((ee(se, _) && ((N = se[_]), (_ = "%" + N[0] + "%")), ee(G, _))) {
        var M = G[_];
        if ((M === $ && (M = ae(_)), typeof M > "u" && !I))
          throw new n(
            "intrinsic " +
              P +
              " exists, but is not available. Please file an issue!",
          );
        return { alias: N, name: _, value: M };
      }
      throw new i("intrinsic " + P + " does not exist!");
    };
  return (
    (Jr = function (P, I) {
      if (typeof P != "string" || P.length === 0)
        throw new n("intrinsic name must be a non-empty string");
      if (arguments.length > 1 && typeof I != "boolean")
        throw new n('"allowMissing" argument must be a boolean');
      if (z(/^%?[^%]*%?$/, P) === null)
        throw new i(
          "`%` may not be present anywhere but at the beginning and end of the intrinsic name",
        );
      var _ = Z(P),
        N = _.length > 0 ? _[0] : "",
        M = ne("%" + N + "%", I),
        K = M.name,
        U = M.value,
        oe = !1,
        le = M.alias;
      le && ((N = le[0]), F(_, x([0, 1], le)));
      for (var ue = 1, fe = !0; ue < _.length; ue += 1) {
        var V = _[ue],
          ce = L(V, 0, 1),
          pe = L(V, -1);
        if (
          (ce === '"' ||
            ce === "'" ||
            ce === "`" ||
            pe === '"' ||
            pe === "'" ||
            pe === "`") &&
          ce !== pe
        )
          throw new i("property names with quotes must have matching quotes");
        if (
          ((V === "constructor" || !fe) && (oe = !0),
          (N += "." + V),
          (K = "%" + N + "%"),
          ee(G, K))
        )
          U = G[K];
        else if (U != null) {
          if (!(V in U)) {
            if (!I)
              throw new n(
                "base intrinsic for " +
                  P +
                  " exists, but the property is not available.",
              );
            return;
          }
          if (s && ue + 1 >= _.length) {
            var ye = s(U, V);
            ((fe = !!ye),
              fe && "get" in ye && !("originalValue" in ye.get)
                ? (U = ye.get)
                : (U = U[V]));
          } else ((fe = ee(U, V)), (U = U[V]));
          fe && !oe && (G[K] = U);
        }
      }
      return U;
    }),
    Jr
  );
}
var Qr, Ln;
function Ja() {
  return (Ln || ((Ln = 1), (Qr = Object)), Qr);
}
var Yr, Wn;
function Qa() {
  return (Wn || ((Wn = 1), (Yr = Object.getOwnPropertyDescriptor)), Yr);
}
var Zr, zn;
function Ya() {
  if (zn) return Zr;
  zn = 1;
  var e = Qa();
  if (e)
    try {
      e([], "length");
    } catch {
      e = null;
    }
  return ((Zr = e), Zr);
}
var Xr, Hn;
function Za() {
  return (
    Hn ||
      ((Hn = 1),
      (Xr = function () {
        if (
          typeof Symbol != "function" ||
          typeof Object.getOwnPropertySymbols != "function"
        )
          return !1;
        if (typeof Symbol.iterator == "symbol") return !0;
        var t = {},
          r = Symbol("test"),
          a = Object(r);
        if (
          typeof r == "string" ||
          Object.prototype.toString.call(r) !== "[object Symbol]" ||
          Object.prototype.toString.call(a) !== "[object Symbol]"
        )
          return !1;
        var m = 42;
        t[r] = m;
        for (var o in t) return !1;
        if (
          (typeof Object.keys == "function" && Object.keys(t).length !== 0) ||
          (typeof Object.getOwnPropertyNames == "function" &&
            Object.getOwnPropertyNames(t).length !== 0)
        )
          return !1;
        var i = Object.getOwnPropertySymbols(t);
        if (
          i.length !== 1 ||
          i[0] !== r ||
          !Object.prototype.propertyIsEnumerable.call(t, r)
        )
          return !1;
        if (typeof Object.getOwnPropertyDescriptor == "function") {
          var n = Object.getOwnPropertyDescriptor(t, r);
          if (n.value !== m || n.enumerable !== !0) return !1;
        }
        return !0;
      })),
    Xr
  );
}
var et, Kn;
function Xa() {
  if (Kn) return et;
  Kn = 1;
  var e = typeof Symbol < "u" && Symbol,
    t = Za();
  return (
    (et = function () {
      return typeof e != "function" ||
        typeof Symbol != "function" ||
        typeof e("foo") != "symbol" ||
        typeof Symbol("bar") != "symbol"
        ? !1
        : t();
    }),
    et
  );
}
var rt, Vn;
function ei() {
  if (Vn) return rt;
  Vn = 1;
  var e,
    t = Ja(),
    r = Pt(),
    a = Ot(),
    m = Rt(),
    o = _t(),
    i = It(),
    n = Pe(),
    v = xt(),
    c = $t(),
    u = Tt(),
    h = Nt(),
    g = Ct(),
    p = Ft(),
    b = kt(),
    E = Dt(),
    l = Function,
    d = function (D) {
      try {
        return l('"use strict"; return (' + D + ").constructor;")();
      } catch {}
    },
    s = Ya(),
    w = Ut(),
    S = function () {
      throw new n();
    },
    R = s
      ? (function () {
          try {
            return (arguments.callee, S);
          } catch {
            try {
              return s(arguments, "callee").get;
            } catch {
              return S;
            }
          }
        })()
      : S,
    O = Xa()(),
    A = qt(),
    T = Ye(),
    q = Qe(),
    C = Ze(),
    B = je(),
    $ = {},
    Y = typeof Uint8Array > "u" || !A ? e : A(Uint8Array),
    G = {
      __proto__: null,
      "%AggregateError%": typeof AggregateError > "u" ? e : AggregateError,
      "%Array%": Array,
      "%ArrayBuffer%": typeof ArrayBuffer > "u" ? e : ArrayBuffer,
      "%ArrayIteratorPrototype%": O && A ? A([][Symbol.iterator]()) : e,
      "%AsyncFromSyncIteratorPrototype%": e,
      "%AsyncFunction%": $,
      "%AsyncGenerator%": $,
      "%AsyncGeneratorFunction%": $,
      "%AsyncIteratorPrototype%": $,
      "%Atomics%": typeof Atomics > "u" ? e : Atomics,
      "%BigInt%": typeof BigInt > "u" ? e : BigInt,
      "%BigInt64Array%": typeof BigInt64Array > "u" ? e : BigInt64Array,
      "%BigUint64Array%": typeof BigUint64Array > "u" ? e : BigUint64Array,
      "%Boolean%": Boolean,
      "%DataView%": typeof DataView > "u" ? e : DataView,
      "%Date%": Date,
      "%decodeURI%": decodeURI,
      "%decodeURIComponent%": decodeURIComponent,
      "%encodeURI%": encodeURI,
      "%encodeURIComponent%": encodeURIComponent,
      "%Error%": r,
      "%eval%": eval,
      "%EvalError%": a,
      "%Float16Array%": typeof Float16Array > "u" ? e : Float16Array,
      "%Float32Array%": typeof Float32Array > "u" ? e : Float32Array,
      "%Float64Array%": typeof Float64Array > "u" ? e : Float64Array,
      "%FinalizationRegistry%":
        typeof FinalizationRegistry > "u" ? e : FinalizationRegistry,
      "%Function%": l,
      "%GeneratorFunction%": $,
      "%Int8Array%": typeof Int8Array > "u" ? e : Int8Array,
      "%Int16Array%": typeof Int16Array > "u" ? e : Int16Array,
      "%Int32Array%": typeof Int32Array > "u" ? e : Int32Array,
      "%isFinite%": isFinite,
      "%isNaN%": isNaN,
      "%IteratorPrototype%": O && A ? A(A([][Symbol.iterator]())) : e,
      "%JSON%": typeof JSON == "object" ? JSON : e,
      "%Map%": typeof Map > "u" ? e : Map,
      "%MapIteratorPrototype%":
        typeof Map > "u" || !O || !A ? e : A(new Map()[Symbol.iterator]()),
      "%Math%": Math,
      "%Number%": Number,
      "%Object%": t,
      "%Object.getOwnPropertyDescriptor%": s,
      "%parseFloat%": parseFloat,
      "%parseInt%": parseInt,
      "%Promise%": typeof Promise > "u" ? e : Promise,
      "%Proxy%": typeof Proxy > "u" ? e : Proxy,
      "%RangeError%": m,
      "%ReferenceError%": o,
      "%Reflect%": typeof Reflect > "u" ? e : Reflect,
      "%RegExp%": RegExp,
      "%Set%": typeof Set > "u" ? e : Set,
      "%SetIteratorPrototype%":
        typeof Set > "u" || !O || !A ? e : A(new Set()[Symbol.iterator]()),
      "%SharedArrayBuffer%":
        typeof SharedArrayBuffer > "u" ? e : SharedArrayBuffer,
      "%String%": String,
      "%StringIteratorPrototype%": O && A ? A(""[Symbol.iterator]()) : e,
      "%Symbol%": O ? Symbol : e,
      "%SyntaxError%": i,
      "%ThrowTypeError%": R,
      "%TypedArray%": Y,
      "%TypeError%": n,
      "%Uint8Array%": typeof Uint8Array > "u" ? e : Uint8Array,
      "%Uint8ClampedArray%":
        typeof Uint8ClampedArray > "u" ? e : Uint8ClampedArray,
      "%Uint16Array%": typeof Uint16Array > "u" ? e : Uint16Array,
      "%Uint32Array%": typeof Uint32Array > "u" ? e : Uint32Array,
      "%URIError%": v,
      "%WeakMap%": typeof WeakMap > "u" ? e : WeakMap,
      "%WeakRef%": typeof WeakRef > "u" ? e : WeakRef,
      "%WeakSet%": typeof WeakSet > "u" ? e : WeakSet,
      "%Function.prototype.call%": B,
      "%Function.prototype.apply%": C,
      "%Object.defineProperty%": w,
      "%Object.getPrototypeOf%": T,
      "%Math.abs%": c,
      "%Math.floor%": u,
      "%Math.max%": h,
      "%Math.min%": g,
      "%Math.pow%": p,
      "%Math.round%": b,
      "%Math.sign%": E,
      "%Reflect.getPrototypeOf%": q,
    };
  if (A)
    try {
      null.error;
    } catch (D) {
      var te = A(A(D));
      G["%Error.prototype%"] = te;
    }
  var ae = function D(P) {
      var I;
      if (P === "%AsyncFunction%") I = d("async function () {}");
      else if (P === "%GeneratorFunction%") I = d("function* () {}");
      else if (P === "%AsyncGeneratorFunction%") I = d("async function* () {}");
      else if (P === "%AsyncGenerator%") {
        var _ = D("%AsyncGeneratorFunction%");
        _ && (I = _.prototype);
      } else if (P === "%AsyncIteratorPrototype%") {
        var N = D("%AsyncGenerator%");
        N && A && (I = A(N.prototype));
      }
      return ((G[P] = I), I);
    },
    se = {
      __proto__: null,
      "%ArrayBufferPrototype%": ["ArrayBuffer", "prototype"],
      "%ArrayPrototype%": ["Array", "prototype"],
      "%ArrayProto_entries%": ["Array", "prototype", "entries"],
      "%ArrayProto_forEach%": ["Array", "prototype", "forEach"],
      "%ArrayProto_keys%": ["Array", "prototype", "keys"],
      "%ArrayProto_values%": ["Array", "prototype", "values"],
      "%AsyncFunctionPrototype%": ["AsyncFunction", "prototype"],
      "%AsyncGenerator%": ["AsyncGeneratorFunction", "prototype"],
      "%AsyncGeneratorPrototype%": [
        "AsyncGeneratorFunction",
        "prototype",
        "prototype",
      ],
      "%BooleanPrototype%": ["Boolean", "prototype"],
      "%DataViewPrototype%": ["DataView", "prototype"],
      "%DatePrototype%": ["Date", "prototype"],
      "%ErrorPrototype%": ["Error", "prototype"],
      "%EvalErrorPrototype%": ["EvalError", "prototype"],
      "%Float32ArrayPrototype%": ["Float32Array", "prototype"],
      "%Float64ArrayPrototype%": ["Float64Array", "prototype"],
      "%FunctionPrototype%": ["Function", "prototype"],
      "%Generator%": ["GeneratorFunction", "prototype"],
      "%GeneratorPrototype%": ["GeneratorFunction", "prototype", "prototype"],
      "%Int8ArrayPrototype%": ["Int8Array", "prototype"],
      "%Int16ArrayPrototype%": ["Int16Array", "prototype"],
      "%Int32ArrayPrototype%": ["Int32Array", "prototype"],
      "%JSONParse%": ["JSON", "parse"],
      "%JSONStringify%": ["JSON", "stringify"],
      "%MapPrototype%": ["Map", "prototype"],
      "%NumberPrototype%": ["Number", "prototype"],
      "%ObjectPrototype%": ["Object", "prototype"],
      "%ObjProto_toString%": ["Object", "prototype", "toString"],
      "%ObjProto_valueOf%": ["Object", "prototype", "valueOf"],
      "%PromisePrototype%": ["Promise", "prototype"],
      "%PromiseProto_then%": ["Promise", "prototype", "then"],
      "%Promise_all%": ["Promise", "all"],
      "%Promise_reject%": ["Promise", "reject"],
      "%Promise_resolve%": ["Promise", "resolve"],
      "%RangeErrorPrototype%": ["RangeError", "prototype"],
      "%ReferenceErrorPrototype%": ["ReferenceError", "prototype"],
      "%RegExpPrototype%": ["RegExp", "prototype"],
      "%SetPrototype%": ["Set", "prototype"],
      "%SharedArrayBufferPrototype%": ["SharedArrayBuffer", "prototype"],
      "%StringPrototype%": ["String", "prototype"],
      "%SymbolPrototype%": ["Symbol", "prototype"],
      "%SyntaxErrorPrototype%": ["SyntaxError", "prototype"],
      "%TypedArrayPrototype%": ["TypedArray", "prototype"],
      "%TypeErrorPrototype%": ["TypeError", "prototype"],
      "%Uint8ArrayPrototype%": ["Uint8Array", "prototype"],
      "%Uint8ClampedArrayPrototype%": ["Uint8ClampedArray", "prototype"],
      "%Uint16ArrayPrototype%": ["Uint16Array", "prototype"],
      "%Uint32ArrayPrototype%": ["Uint32Array", "prototype"],
      "%URIErrorPrototype%": ["URIError", "prototype"],
      "%WeakMapPrototype%": ["WeakMap", "prototype"],
      "%WeakSetPrototype%": ["WeakSet", "prototype"],
    },
    k = Ce(),
    ee = Mt(),
    x = k.call(B, Array.prototype.concat),
    F = k.call(C, Array.prototype.splice),
    j = k.call(B, String.prototype.replace),
    L = k.call(B, String.prototype.slice),
    z = k.call(B, RegExp.prototype.exec),
    Q =
      /[^%.[\]]+|\[(?:(-?\d+(?:\.\d+)?)|(["'])((?:(?!\2)[^\\]|\\.)*?)\2)\]|(?=(?:\.|\[\])(?:\.|\[\]|%$))/g,
    H = /\\(\\)?/g,
    Z = function (P) {
      var I = L(P, 0, 1),
        _ = L(P, -1);
      if (I === "%" && _ !== "%")
        throw new i("invalid intrinsic syntax, expected closing `%`");
      if (_ === "%" && I !== "%")
        throw new i("invalid intrinsic syntax, expected opening `%`");
      var N = [];
      return (
        j(P, Q, function (M, K, U, oe) {
          N[N.length] = U ? j(oe, H, "$1") : K || M;
        }),
        N
      );
    },
    ne = function (P, I) {
      var _ = P,
        N;
      if ((ee(se, _) && ((N = se[_]), (_ = "%" + N[0] + "%")), ee(G, _))) {
        var M = G[_];
        if ((M === $ && (M = ae(_)), typeof M > "u" && !I))
          throw new n(
            "intrinsic " +
              P +
              " exists, but is not available. Please file an issue!",
          );
        return { alias: N, name: _, value: M };
      }
      throw new i("intrinsic " + P + " does not exist!");
    };
  return (
    (rt = function (P, I) {
      if (typeof P != "string" || P.length === 0)
        throw new n("intrinsic name must be a non-empty string");
      if (arguments.length > 1 && typeof I != "boolean")
        throw new n('"allowMissing" argument must be a boolean');
      if (z(/^%?[^%]*%?$/, P) === null)
        throw new i(
          "`%` may not be present anywhere but at the beginning and end of the intrinsic name",
        );
      var _ = Z(P),
        N = _.length > 0 ? _[0] : "",
        M = ne("%" + N + "%", I),
        K = M.name,
        U = M.value,
        oe = !1,
        le = M.alias;
      le && ((N = le[0]), F(_, x([0, 1], le)));
      for (var ue = 1, fe = !0; ue < _.length; ue += 1) {
        var V = _[ue],
          ce = L(V, 0, 1),
          pe = L(V, -1);
        if (
          (ce === '"' ||
            ce === "'" ||
            ce === "`" ||
            pe === '"' ||
            pe === "'" ||
            pe === "`") &&
          ce !== pe
        )
          throw new i("property names with quotes must have matching quotes");
        if (
          ((V === "constructor" || !fe) && (oe = !0),
          (N += "." + V),
          (K = "%" + N + "%"),
          ee(G, K))
        )
          U = G[K];
        else if (U != null) {
          if (!(V in U)) {
            if (!I)
              throw new n(
                "base intrinsic for " +
                  P +
                  " exists, but the property is not available.",
              );
            return;
          }
          if (s && ue + 1 >= _.length) {
            var ye = s(U, V);
            ((fe = !!ye),
              fe && "get" in ye && !("originalValue" in ye.get)
                ? (U = ye.get)
                : (U = U[V]));
          } else ((fe = ee(U, V)), (U = U[V]));
          fe && !oe && (G[K] = U);
        }
      }
      return U;
    }),
    rt
  );
}
var tt, Jn;
function Eo() {
  if (Jn) return tt;
  Jn = 1;
  var e = ei(),
    t = So(),
    r = t([e("%String.prototype.indexOf%")]);
  return (
    (tt = function (m, o) {
      var i = e(m, !!o);
      return typeof i == "function" && r(m, ".prototype.") > -1 ? t([i]) : i;
    }),
    tt
  );
}
var nt, Qn;
function wo() {
  if (Qn) return nt;
  Qn = 1;
  var e = Va(),
    t = Eo(),
    r = Je(),
    a = Pe(),
    m = e("%Map%", !0),
    o = t("Map.prototype.get", !0),
    i = t("Map.prototype.set", !0),
    n = t("Map.prototype.has", !0),
    v = t("Map.prototype.delete", !0),
    c = t("Map.prototype.size", !0);
  return (
    (nt =
      !!m &&
      function () {
        var h,
          g = {
            assert: function (p) {
              if (!g.has(p))
                throw new a("Side channel does not contain " + r(p));
            },
            delete: function (p) {
              if (h) {
                var b = v(h, p);
                return (c(h) === 0 && (h = void 0), b);
              }
              return !1;
            },
            get: function (p) {
              if (h) return o(h, p);
            },
            has: function (p) {
              return h ? n(h, p) : !1;
            },
            set: function (p, b) {
              (h || (h = new m()), i(h, p, b));
            },
          };
        return g;
      }),
    nt
  );
}
var ot, Yn;
function ri() {
  return (Yn || ((Yn = 1), (ot = Object)), ot);
}
var at, Zn;
function ti() {
  return (Zn || ((Zn = 1), (at = Object.getOwnPropertyDescriptor)), at);
}
var it, Xn;
function ni() {
  if (Xn) return it;
  Xn = 1;
  var e = ti();
  if (e)
    try {
      e([], "length");
    } catch {
      e = null;
    }
  return ((it = e), it);
}
var st, eo;
function oi() {
  return (
    eo ||
      ((eo = 1),
      (st = function () {
        if (
          typeof Symbol != "function" ||
          typeof Object.getOwnPropertySymbols != "function"
        )
          return !1;
        if (typeof Symbol.iterator == "symbol") return !0;
        var t = {},
          r = Symbol("test"),
          a = Object(r);
        if (
          typeof r == "string" ||
          Object.prototype.toString.call(r) !== "[object Symbol]" ||
          Object.prototype.toString.call(a) !== "[object Symbol]"
        )
          return !1;
        var m = 42;
        t[r] = m;
        for (var o in t) return !1;
        if (
          (typeof Object.keys == "function" && Object.keys(t).length !== 0) ||
          (typeof Object.getOwnPropertyNames == "function" &&
            Object.getOwnPropertyNames(t).length !== 0)
        )
          return !1;
        var i = Object.getOwnPropertySymbols(t);
        if (
          i.length !== 1 ||
          i[0] !== r ||
          !Object.prototype.propertyIsEnumerable.call(t, r)
        )
          return !1;
        if (typeof Object.getOwnPropertyDescriptor == "function") {
          var n = Object.getOwnPropertyDescriptor(t, r);
          if (n.value !== m || n.enumerable !== !0) return !1;
        }
        return !0;
      })),
    st
  );
}
var lt, ro;
function ai() {
  if (ro) return lt;
  ro = 1;
  var e = typeof Symbol < "u" && Symbol,
    t = oi();
  return (
    (lt = function () {
      return typeof e != "function" ||
        typeof Symbol != "function" ||
        typeof e("foo") != "symbol" ||
        typeof Symbol("bar") != "symbol"
        ? !1
        : t();
    }),
    lt
  );
}
var ft, to;
function ii() {
  if (to) return ft;
  to = 1;
  var e,
    t = ri(),
    r = Pt(),
    a = Ot(),
    m = Rt(),
    o = _t(),
    i = It(),
    n = Pe(),
    v = xt(),
    c = $t(),
    u = Tt(),
    h = Nt(),
    g = Ct(),
    p = Ft(),
    b = kt(),
    E = Dt(),
    l = Function,
    d = function (D) {
      try {
        return l('"use strict"; return (' + D + ").constructor;")();
      } catch {}
    },
    s = ni(),
    w = Ut(),
    S = function () {
      throw new n();
    },
    R = s
      ? (function () {
          try {
            return (arguments.callee, S);
          } catch {
            try {
              return s(arguments, "callee").get;
            } catch {
              return S;
            }
          }
        })()
      : S,
    O = ai()(),
    A = qt(),
    T = Ye(),
    q = Qe(),
    C = Ze(),
    B = je(),
    $ = {},
    Y = typeof Uint8Array > "u" || !A ? e : A(Uint8Array),
    G = {
      __proto__: null,
      "%AggregateError%": typeof AggregateError > "u" ? e : AggregateError,
      "%Array%": Array,
      "%ArrayBuffer%": typeof ArrayBuffer > "u" ? e : ArrayBuffer,
      "%ArrayIteratorPrototype%": O && A ? A([][Symbol.iterator]()) : e,
      "%AsyncFromSyncIteratorPrototype%": e,
      "%AsyncFunction%": $,
      "%AsyncGenerator%": $,
      "%AsyncGeneratorFunction%": $,
      "%AsyncIteratorPrototype%": $,
      "%Atomics%": typeof Atomics > "u" ? e : Atomics,
      "%BigInt%": typeof BigInt > "u" ? e : BigInt,
      "%BigInt64Array%": typeof BigInt64Array > "u" ? e : BigInt64Array,
      "%BigUint64Array%": typeof BigUint64Array > "u" ? e : BigUint64Array,
      "%Boolean%": Boolean,
      "%DataView%": typeof DataView > "u" ? e : DataView,
      "%Date%": Date,
      "%decodeURI%": decodeURI,
      "%decodeURIComponent%": decodeURIComponent,
      "%encodeURI%": encodeURI,
      "%encodeURIComponent%": encodeURIComponent,
      "%Error%": r,
      "%eval%": eval,
      "%EvalError%": a,
      "%Float16Array%": typeof Float16Array > "u" ? e : Float16Array,
      "%Float32Array%": typeof Float32Array > "u" ? e : Float32Array,
      "%Float64Array%": typeof Float64Array > "u" ? e : Float64Array,
      "%FinalizationRegistry%":
        typeof FinalizationRegistry > "u" ? e : FinalizationRegistry,
      "%Function%": l,
      "%GeneratorFunction%": $,
      "%Int8Array%": typeof Int8Array > "u" ? e : Int8Array,
      "%Int16Array%": typeof Int16Array > "u" ? e : Int16Array,
      "%Int32Array%": typeof Int32Array > "u" ? e : Int32Array,
      "%isFinite%": isFinite,
      "%isNaN%": isNaN,
      "%IteratorPrototype%": O && A ? A(A([][Symbol.iterator]())) : e,
      "%JSON%": typeof JSON == "object" ? JSON : e,
      "%Map%": typeof Map > "u" ? e : Map,
      "%MapIteratorPrototype%":
        typeof Map > "u" || !O || !A ? e : A(new Map()[Symbol.iterator]()),
      "%Math%": Math,
      "%Number%": Number,
      "%Object%": t,
      "%Object.getOwnPropertyDescriptor%": s,
      "%parseFloat%": parseFloat,
      "%parseInt%": parseInt,
      "%Promise%": typeof Promise > "u" ? e : Promise,
      "%Proxy%": typeof Proxy > "u" ? e : Proxy,
      "%RangeError%": m,
      "%ReferenceError%": o,
      "%Reflect%": typeof Reflect > "u" ? e : Reflect,
      "%RegExp%": RegExp,
      "%Set%": typeof Set > "u" ? e : Set,
      "%SetIteratorPrototype%":
        typeof Set > "u" || !O || !A ? e : A(new Set()[Symbol.iterator]()),
      "%SharedArrayBuffer%":
        typeof SharedArrayBuffer > "u" ? e : SharedArrayBuffer,
      "%String%": String,
      "%StringIteratorPrototype%": O && A ? A(""[Symbol.iterator]()) : e,
      "%Symbol%": O ? Symbol : e,
      "%SyntaxError%": i,
      "%ThrowTypeError%": R,
      "%TypedArray%": Y,
      "%TypeError%": n,
      "%Uint8Array%": typeof Uint8Array > "u" ? e : Uint8Array,
      "%Uint8ClampedArray%":
        typeof Uint8ClampedArray > "u" ? e : Uint8ClampedArray,
      "%Uint16Array%": typeof Uint16Array > "u" ? e : Uint16Array,
      "%Uint32Array%": typeof Uint32Array > "u" ? e : Uint32Array,
      "%URIError%": v,
      "%WeakMap%": typeof WeakMap > "u" ? e : WeakMap,
      "%WeakRef%": typeof WeakRef > "u" ? e : WeakRef,
      "%WeakSet%": typeof WeakSet > "u" ? e : WeakSet,
      "%Function.prototype.call%": B,
      "%Function.prototype.apply%": C,
      "%Object.defineProperty%": w,
      "%Object.getPrototypeOf%": T,
      "%Math.abs%": c,
      "%Math.floor%": u,
      "%Math.max%": h,
      "%Math.min%": g,
      "%Math.pow%": p,
      "%Math.round%": b,
      "%Math.sign%": E,
      "%Reflect.getPrototypeOf%": q,
    };
  if (A)
    try {
      null.error;
    } catch (D) {
      var te = A(A(D));
      G["%Error.prototype%"] = te;
    }
  var ae = function D(P) {
      var I;
      if (P === "%AsyncFunction%") I = d("async function () {}");
      else if (P === "%GeneratorFunction%") I = d("function* () {}");
      else if (P === "%AsyncGeneratorFunction%") I = d("async function* () {}");
      else if (P === "%AsyncGenerator%") {
        var _ = D("%AsyncGeneratorFunction%");
        _ && (I = _.prototype);
      } else if (P === "%AsyncIteratorPrototype%") {
        var N = D("%AsyncGenerator%");
        N && A && (I = A(N.prototype));
      }
      return ((G[P] = I), I);
    },
    se = {
      __proto__: null,
      "%ArrayBufferPrototype%": ["ArrayBuffer", "prototype"],
      "%ArrayPrototype%": ["Array", "prototype"],
      "%ArrayProto_entries%": ["Array", "prototype", "entries"],
      "%ArrayProto_forEach%": ["Array", "prototype", "forEach"],
      "%ArrayProto_keys%": ["Array", "prototype", "keys"],
      "%ArrayProto_values%": ["Array", "prototype", "values"],
      "%AsyncFunctionPrototype%": ["AsyncFunction", "prototype"],
      "%AsyncGenerator%": ["AsyncGeneratorFunction", "prototype"],
      "%AsyncGeneratorPrototype%": [
        "AsyncGeneratorFunction",
        "prototype",
        "prototype",
      ],
      "%BooleanPrototype%": ["Boolean", "prototype"],
      "%DataViewPrototype%": ["DataView", "prototype"],
      "%DatePrototype%": ["Date", "prototype"],
      "%ErrorPrototype%": ["Error", "prototype"],
      "%EvalErrorPrototype%": ["EvalError", "prototype"],
      "%Float32ArrayPrototype%": ["Float32Array", "prototype"],
      "%Float64ArrayPrototype%": ["Float64Array", "prototype"],
      "%FunctionPrototype%": ["Function", "prototype"],
      "%Generator%": ["GeneratorFunction", "prototype"],
      "%GeneratorPrototype%": ["GeneratorFunction", "prototype", "prototype"],
      "%Int8ArrayPrototype%": ["Int8Array", "prototype"],
      "%Int16ArrayPrototype%": ["Int16Array", "prototype"],
      "%Int32ArrayPrototype%": ["Int32Array", "prototype"],
      "%JSONParse%": ["JSON", "parse"],
      "%JSONStringify%": ["JSON", "stringify"],
      "%MapPrototype%": ["Map", "prototype"],
      "%NumberPrototype%": ["Number", "prototype"],
      "%ObjectPrototype%": ["Object", "prototype"],
      "%ObjProto_toString%": ["Object", "prototype", "toString"],
      "%ObjProto_valueOf%": ["Object", "prototype", "valueOf"],
      "%PromisePrototype%": ["Promise", "prototype"],
      "%PromiseProto_then%": ["Promise", "prototype", "then"],
      "%Promise_all%": ["Promise", "all"],
      "%Promise_reject%": ["Promise", "reject"],
      "%Promise_resolve%": ["Promise", "resolve"],
      "%RangeErrorPrototype%": ["RangeError", "prototype"],
      "%ReferenceErrorPrototype%": ["ReferenceError", "prototype"],
      "%RegExpPrototype%": ["RegExp", "prototype"],
      "%SetPrototype%": ["Set", "prototype"],
      "%SharedArrayBufferPrototype%": ["SharedArrayBuffer", "prototype"],
      "%StringPrototype%": ["String", "prototype"],
      "%SymbolPrototype%": ["Symbol", "prototype"],
      "%SyntaxErrorPrototype%": ["SyntaxError", "prototype"],
      "%TypedArrayPrototype%": ["TypedArray", "prototype"],
      "%TypeErrorPrototype%": ["TypeError", "prototype"],
      "%Uint8ArrayPrototype%": ["Uint8Array", "prototype"],
      "%Uint8ClampedArrayPrototype%": ["Uint8ClampedArray", "prototype"],
      "%Uint16ArrayPrototype%": ["Uint16Array", "prototype"],
      "%Uint32ArrayPrototype%": ["Uint32Array", "prototype"],
      "%URIErrorPrototype%": ["URIError", "prototype"],
      "%WeakMapPrototype%": ["WeakMap", "prototype"],
      "%WeakSetPrototype%": ["WeakSet", "prototype"],
    },
    k = Ce(),
    ee = Mt(),
    x = k.call(B, Array.prototype.concat),
    F = k.call(C, Array.prototype.splice),
    j = k.call(B, String.prototype.replace),
    L = k.call(B, String.prototype.slice),
    z = k.call(B, RegExp.prototype.exec),
    Q =
      /[^%.[\]]+|\[(?:(-?\d+(?:\.\d+)?)|(["'])((?:(?!\2)[^\\]|\\.)*?)\2)\]|(?=(?:\.|\[\])(?:\.|\[\]|%$))/g,
    H = /\\(\\)?/g,
    Z = function (P) {
      var I = L(P, 0, 1),
        _ = L(P, -1);
      if (I === "%" && _ !== "%")
        throw new i("invalid intrinsic syntax, expected closing `%`");
      if (_ === "%" && I !== "%")
        throw new i("invalid intrinsic syntax, expected opening `%`");
      var N = [];
      return (
        j(P, Q, function (M, K, U, oe) {
          N[N.length] = U ? j(oe, H, "$1") : K || M;
        }),
        N
      );
    },
    ne = function (P, I) {
      var _ = P,
        N;
      if ((ee(se, _) && ((N = se[_]), (_ = "%" + N[0] + "%")), ee(G, _))) {
        var M = G[_];
        if ((M === $ && (M = ae(_)), typeof M > "u" && !I))
          throw new n(
            "intrinsic " +
              P +
              " exists, but is not available. Please file an issue!",
          );
        return { alias: N, name: _, value: M };
      }
      throw new i("intrinsic " + P + " does not exist!");
    };
  return (
    (ft = function (P, I) {
      if (typeof P != "string" || P.length === 0)
        throw new n("intrinsic name must be a non-empty string");
      if (arguments.length > 1 && typeof I != "boolean")
        throw new n('"allowMissing" argument must be a boolean');
      if (z(/^%?[^%]*%?$/, P) === null)
        throw new i(
          "`%` may not be present anywhere but at the beginning and end of the intrinsic name",
        );
      var _ = Z(P),
        N = _.length > 0 ? _[0] : "",
        M = ne("%" + N + "%", I),
        K = M.name,
        U = M.value,
        oe = !1,
        le = M.alias;
      le && ((N = le[0]), F(_, x([0, 1], le)));
      for (var ue = 1, fe = !0; ue < _.length; ue += 1) {
        var V = _[ue],
          ce = L(V, 0, 1),
          pe = L(V, -1);
        if (
          (ce === '"' ||
            ce === "'" ||
            ce === "`" ||
            pe === '"' ||
            pe === "'" ||
            pe === "`") &&
          ce !== pe
        )
          throw new i("property names with quotes must have matching quotes");
        if (
          ((V === "constructor" || !fe) && (oe = !0),
          (N += "." + V),
          (K = "%" + N + "%"),
          ee(G, K))
        )
          U = G[K];
        else if (U != null) {
          if (!(V in U)) {
            if (!I)
              throw new n(
                "base intrinsic for " +
                  P +
                  " exists, but the property is not available.",
              );
            return;
          }
          if (s && ue + 1 >= _.length) {
            var ye = s(U, V);
            ((fe = !!ye),
              fe && "get" in ye && !("originalValue" in ye.get)
                ? (U = ye.get)
                : (U = U[V]));
          } else ((fe = ee(U, V)), (U = U[V]));
          fe && !oe && (G[K] = U);
        }
      }
      return U;
    }),
    ft
  );
}
var ut, no;
function si() {
  if (no) return ut;
  no = 1;
  var e = ii(),
    t = Eo(),
    r = Je(),
    a = wo(),
    m = Pe(),
    o = e("%WeakMap%", !0),
    i = t("WeakMap.prototype.get", !0),
    n = t("WeakMap.prototype.set", !0),
    v = t("WeakMap.prototype.has", !0),
    c = t("WeakMap.prototype.delete", !0);
  return (
    (ut = o
      ? function () {
          var h,
            g,
            p = {
              assert: function (b) {
                if (!p.has(b))
                  throw new m("Side channel does not contain " + r(b));
              },
              delete: function (b) {
                if (
                  o &&
                  b &&
                  (typeof b == "object" || typeof b == "function")
                ) {
                  if (h) return c(h, b);
                } else if (a && g) return g.delete(b);
                return !1;
              },
              get: function (b) {
                return o &&
                  b &&
                  (typeof b == "object" || typeof b == "function") &&
                  h
                  ? i(h, b)
                  : g && g.get(b);
              },
              has: function (b) {
                return o &&
                  b &&
                  (typeof b == "object" || typeof b == "function") &&
                  h
                  ? v(h, b)
                  : !!g && g.has(b);
              },
              set: function (b, E) {
                o && b && (typeof b == "object" || typeof b == "function")
                  ? (h || (h = new o()), n(h, b, E))
                  : a && (g || (g = a()), g.set(b, E));
              },
            };
          return p;
        }
      : a),
    ut
  );
}
var ct, oo;
function li() {
  if (oo) return ct;
  oo = 1;
  var e = Pe(),
    t = Je(),
    r = Fa(),
    a = wo(),
    m = si(),
    o = m || a || r;
  return (
    (ct = function () {
      var n,
        v = {
          assert: function (c) {
            if (!v.has(c)) throw new e("Side channel does not contain " + t(c));
          },
          delete: function (c) {
            return !!n && n.delete(c);
          },
          get: function (c) {
            return n && n.get(c);
          },
          has: function (c) {
            return !!n && n.has(c);
          },
          set: function (c, u) {
            (n || (n = o()), n.set(c, u));
          },
        };
      return v;
    }),
    ct
  );
}
var pt, ao;
function jt() {
  if (ao) return pt;
  ao = 1;
  var e = String.prototype.replace,
    t = /%20/g,
    r = { RFC1738: "RFC1738", RFC3986: "RFC3986" };
  return (
    (pt = {
      default: r.RFC3986,
      formatters: {
        RFC1738: function (a) {
          return e.call(a, t, "+");
        },
        RFC3986: function (a) {
          return String(a);
        },
      },
      RFC1738: r.RFC1738,
      RFC3986: r.RFC3986,
    }),
    pt
  );
}
var yt, io;
function Po() {
  if (io) return yt;
  io = 1;
  var e = jt(),
    t = Object.prototype.hasOwnProperty,
    r = Array.isArray,
    a = (function () {
      for (var l = [], d = 0; d < 256; ++d)
        l.push("%" + ((d < 16 ? "0" : "") + d.toString(16)).toUpperCase());
      return l;
    })(),
    m = function (d) {
      for (; d.length > 1;) {
        var s = d.pop(),
          w = s.obj[s.prop];
        if (r(w)) {
          for (var S = [], R = 0; R < w.length; ++R)
            typeof w[R] < "u" && S.push(w[R]);
          s.obj[s.prop] = S;
        }
      }
    },
    o = function (d, s) {
      for (
        var w = s && s.plainObjects ? { __proto__: null } : {}, S = 0;
        S < d.length;
        ++S
      )
        typeof d[S] < "u" && (w[S] = d[S]);
      return w;
    },
    i = function l(d, s, w) {
      if (!s) return d;
      if (typeof s != "object" && typeof s != "function") {
        if (r(d)) d.push(s);
        else if (d && typeof d == "object")
          ((w && (w.plainObjects || w.allowPrototypes)) ||
            !t.call(Object.prototype, s)) &&
            (d[s] = !0);
        else return [d, s];
        return d;
      }
      if (!d || typeof d != "object") return [d].concat(s);
      var S = d;
      return (
        r(d) && !r(s) && (S = o(d, w)),
        r(d) && r(s)
          ? (s.forEach(function (R, O) {
              if (t.call(d, O)) {
                var A = d[O];
                A && typeof A == "object" && R && typeof R == "object"
                  ? (d[O] = l(A, R, w))
                  : d.push(R);
              } else d[O] = R;
            }),
            d)
          : Object.keys(s).reduce(function (R, O) {
              var A = s[O];
              return (t.call(R, O) ? (R[O] = l(R[O], A, w)) : (R[O] = A), R);
            }, S)
      );
    },
    n = function (d, s) {
      return Object.keys(s).reduce(function (w, S) {
        return ((w[S] = s[S]), w);
      }, d);
    },
    v = function (l, d, s) {
      var w = l.replace(/\+/g, " ");
      if (s === "iso-8859-1") return w.replace(/%[0-9a-f]{2}/gi, unescape);
      try {
        return decodeURIComponent(w);
      } catch {
        return w;
      }
    },
    c = 1024,
    u = function (d, s, w, S, R) {
      if (d.length === 0) return d;
      var O = d;
      if (
        (typeof d == "symbol"
          ? (O = Symbol.prototype.toString.call(d))
          : typeof d != "string" && (O = String(d)),
        w === "iso-8859-1")
      )
        return escape(O).replace(/%u[0-9a-f]{4}/gi, function (Y) {
          return "%26%23" + parseInt(Y.slice(2), 16) + "%3B";
        });
      for (var A = "", T = 0; T < O.length; T += c) {
        for (
          var q = O.length >= c ? O.slice(T, T + c) : O, C = [], B = 0;
          B < q.length;
          ++B
        ) {
          var $ = q.charCodeAt(B);
          if (
            $ === 45 ||
            $ === 46 ||
            $ === 95 ||
            $ === 126 ||
            ($ >= 48 && $ <= 57) ||
            ($ >= 65 && $ <= 90) ||
            ($ >= 97 && $ <= 122) ||
            (R === e.RFC1738 && ($ === 40 || $ === 41))
          ) {
            C[C.length] = q.charAt(B);
            continue;
          }
          if ($ < 128) {
            C[C.length] = a[$];
            continue;
          }
          if ($ < 2048) {
            C[C.length] = a[192 | ($ >> 6)] + a[128 | ($ & 63)];
            continue;
          }
          if ($ < 55296 || $ >= 57344) {
            C[C.length] =
              a[224 | ($ >> 12)] + a[128 | (($ >> 6) & 63)] + a[128 | ($ & 63)];
            continue;
          }
          ((B += 1),
            ($ = 65536 + ((($ & 1023) << 10) | (q.charCodeAt(B) & 1023))),
            (C[C.length] =
              a[240 | ($ >> 18)] +
              a[128 | (($ >> 12) & 63)] +
              a[128 | (($ >> 6) & 63)] +
              a[128 | ($ & 63)]));
        }
        A += C.join("");
      }
      return A;
    },
    h = function (d) {
      for (
        var s = [{ obj: { o: d }, prop: "o" }], w = [], S = 0;
        S < s.length;
        ++S
      )
        for (
          var R = s[S], O = R.obj[R.prop], A = Object.keys(O), T = 0;
          T < A.length;
          ++T
        ) {
          var q = A[T],
            C = O[q];
          typeof C == "object" &&
            C !== null &&
            w.indexOf(C) === -1 &&
            (s.push({ obj: O, prop: q }), w.push(C));
        }
      return (m(s), d);
    },
    g = function (d) {
      return Object.prototype.toString.call(d) === "[object RegExp]";
    },
    p = function (d) {
      return !d || typeof d != "object"
        ? !1
        : !!(
            d.constructor &&
            d.constructor.isBuffer &&
            d.constructor.isBuffer(d)
          );
    },
    b = function (d, s) {
      return [].concat(d, s);
    },
    E = function (d, s) {
      if (r(d)) {
        for (var w = [], S = 0; S < d.length; S += 1) w.push(s(d[S]));
        return w;
      }
      return s(d);
    };
  return (
    (yt = {
      arrayToObject: o,
      assign: n,
      combine: b,
      compact: h,
      decode: v,
      encode: u,
      isBuffer: p,
      isRegExp: g,
      maybeMap: E,
      merge: i,
    }),
    yt
  );
}
var dt, so;
function fi() {
  if (so) return dt;
  so = 1;
  var e = li(),
    t = Po(),
    r = jt(),
    a = Object.prototype.hasOwnProperty,
    m = {
      brackets: function (l) {
        return l + "[]";
      },
      comma: "comma",
      indices: function (l, d) {
        return l + "[" + d + "]";
      },
      repeat: function (l) {
        return l;
      },
    },
    o = Array.isArray,
    i = Array.prototype.push,
    n = function (E, l) {
      i.apply(E, o(l) ? l : [l]);
    },
    v = Date.prototype.toISOString,
    c = r.default,
    u = {
      addQueryPrefix: !1,
      allowDots: !1,
      allowEmptyArrays: !1,
      arrayFormat: "indices",
      charset: "utf-8",
      charsetSentinel: !1,
      commaRoundTrip: !1,
      delimiter: "&",
      encode: !0,
      encodeDotInKeys: !1,
      encoder: t.encode,
      encodeValuesOnly: !1,
      filter: void 0,
      format: c,
      formatter: r.formatters[c],
      indices: !1,
      serializeDate: function (l) {
        return v.call(l);
      },
      skipNulls: !1,
      strictNullHandling: !1,
    },
    h = function (l) {
      return (
        typeof l == "string" ||
        typeof l == "number" ||
        typeof l == "boolean" ||
        typeof l == "symbol" ||
        typeof l == "bigint"
      );
    },
    g = {},
    p = function E(l, d, s, w, S, R, O, A, T, q, C, B, $, Y, G, te, ae, se) {
      for (
        var k = l, ee = se, x = 0, F = !1;
        (ee = ee.get(g)) !== void 0 && !F;
      ) {
        var j = ee.get(l);
        if (((x += 1), typeof j < "u")) {
          if (j === x) throw new RangeError("Cyclic object value");
          F = !0;
        }
        typeof ee.get(g) > "u" && (x = 0);
      }
      if (
        (typeof q == "function"
          ? (k = q(d, k))
          : k instanceof Date
            ? (k = $(k))
            : s === "comma" &&
              o(k) &&
              (k = t.maybeMap(k, function (K) {
                return K instanceof Date ? $(K) : K;
              })),
        k === null)
      ) {
        if (R) return T && !te ? T(d, u.encoder, ae, "key", Y) : d;
        k = "";
      }
      if (h(k) || t.isBuffer(k)) {
        if (T) {
          var L = te ? d : T(d, u.encoder, ae, "key", Y);
          return [G(L) + "=" + G(T(k, u.encoder, ae, "value", Y))];
        }
        return [G(d) + "=" + G(String(k))];
      }
      var z = [];
      if (typeof k > "u") return z;
      var Q;
      if (s === "comma" && o(k))
        (te && T && (k = t.maybeMap(k, T)),
          (Q = [{ value: k.length > 0 ? k.join(",") || null : void 0 }]));
      else if (o(q)) Q = q;
      else {
        var H = Object.keys(k);
        Q = C ? H.sort(C) : H;
      }
      var Z = A ? String(d).replace(/\./g, "%2E") : String(d),
        ne = w && o(k) && k.length === 1 ? Z + "[]" : Z;
      if (S && o(k) && k.length === 0) return ne + "[]";
      for (var D = 0; D < Q.length; ++D) {
        var P = Q[D],
          I =
            typeof P == "object" && P && typeof P.value < "u" ? P.value : k[P];
        if (!(O && I === null)) {
          var _ = B && A ? String(P).replace(/\./g, "%2E") : String(P),
            N = o(k)
              ? typeof s == "function"
                ? s(ne, _)
                : ne
              : ne + (B ? "." + _ : "[" + _ + "]");
          se.set(l, x);
          var M = e();
          (M.set(g, se),
            n(
              z,
              E(
                I,
                N,
                s,
                w,
                S,
                R,
                O,
                A,
                s === "comma" && te && o(k) ? null : T,
                q,
                C,
                B,
                $,
                Y,
                G,
                te,
                ae,
                M,
              ),
            ));
        }
      }
      return z;
    },
    b = function (l) {
      if (!l) return u;
      if (
        typeof l.allowEmptyArrays < "u" &&
        typeof l.allowEmptyArrays != "boolean"
      )
        throw new TypeError(
          "`allowEmptyArrays` option can only be `true` or `false`, when provided",
        );
      if (
        typeof l.encodeDotInKeys < "u" &&
        typeof l.encodeDotInKeys != "boolean"
      )
        throw new TypeError(
          "`encodeDotInKeys` option can only be `true` or `false`, when provided",
        );
      if (
        l.encoder !== null &&
        typeof l.encoder < "u" &&
        typeof l.encoder != "function"
      )
        throw new TypeError("Encoder has to be a function.");
      var d = l.charset || u.charset;
      if (
        typeof l.charset < "u" &&
        l.charset !== "utf-8" &&
        l.charset !== "iso-8859-1"
      )
        throw new TypeError(
          "The charset option must be either utf-8, iso-8859-1, or undefined",
        );
      var s = r.default;
      if (typeof l.format < "u") {
        if (!a.call(r.formatters, l.format))
          throw new TypeError("Unknown format option provided.");
        s = l.format;
      }
      var w = r.formatters[s],
        S = u.filter;
      (typeof l.filter == "function" || o(l.filter)) && (S = l.filter);
      var R;
      if (
        (l.arrayFormat in m
          ? (R = l.arrayFormat)
          : "indices" in l
            ? (R = l.indices ? "indices" : "repeat")
            : (R = u.arrayFormat),
        "commaRoundTrip" in l && typeof l.commaRoundTrip != "boolean")
      )
        throw new TypeError("`commaRoundTrip` must be a boolean, or absent");
      var O =
        typeof l.allowDots > "u"
          ? l.encodeDotInKeys === !0
            ? !0
            : u.allowDots
          : !!l.allowDots;
      return {
        addQueryPrefix:
          typeof l.addQueryPrefix == "boolean"
            ? l.addQueryPrefix
            : u.addQueryPrefix,
        allowDots: O,
        allowEmptyArrays:
          typeof l.allowEmptyArrays == "boolean"
            ? !!l.allowEmptyArrays
            : u.allowEmptyArrays,
        arrayFormat: R,
        charset: d,
        charsetSentinel:
          typeof l.charsetSentinel == "boolean"
            ? l.charsetSentinel
            : u.charsetSentinel,
        commaRoundTrip: !!l.commaRoundTrip,
        delimiter: typeof l.delimiter > "u" ? u.delimiter : l.delimiter,
        encode: typeof l.encode == "boolean" ? l.encode : u.encode,
        encodeDotInKeys:
          typeof l.encodeDotInKeys == "boolean"
            ? l.encodeDotInKeys
            : u.encodeDotInKeys,
        encoder: typeof l.encoder == "function" ? l.encoder : u.encoder,
        encodeValuesOnly:
          typeof l.encodeValuesOnly == "boolean"
            ? l.encodeValuesOnly
            : u.encodeValuesOnly,
        filter: S,
        format: s,
        formatter: w,
        serializeDate:
          typeof l.serializeDate == "function"
            ? l.serializeDate
            : u.serializeDate,
        skipNulls: typeof l.skipNulls == "boolean" ? l.skipNulls : u.skipNulls,
        sort: typeof l.sort == "function" ? l.sort : null,
        strictNullHandling:
          typeof l.strictNullHandling == "boolean"
            ? l.strictNullHandling
            : u.strictNullHandling,
      };
    };
  return (
    (dt = function (E, l) {
      var d = E,
        s = b(l),
        w,
        S;
      typeof s.filter == "function"
        ? ((S = s.filter), (d = S("", d)))
        : o(s.filter) && ((S = s.filter), (w = S));
      var R = [];
      if (typeof d != "object" || d === null) return "";
      var O = m[s.arrayFormat],
        A = O === "comma" && s.commaRoundTrip;
      (w || (w = Object.keys(d)), s.sort && w.sort(s.sort));
      for (var T = e(), q = 0; q < w.length; ++q) {
        var C = w[q],
          B = d[C];
        (s.skipNulls && B === null) ||
          n(
            R,
            p(
              B,
              C,
              O,
              A,
              s.allowEmptyArrays,
              s.strictNullHandling,
              s.skipNulls,
              s.encodeDotInKeys,
              s.encode ? s.encoder : null,
              s.filter,
              s.sort,
              s.allowDots,
              s.serializeDate,
              s.format,
              s.formatter,
              s.encodeValuesOnly,
              s.charset,
              T,
            ),
          );
      }
      var $ = R.join(s.delimiter),
        Y = s.addQueryPrefix === !0 ? "?" : "";
      return (
        s.charsetSentinel &&
          (s.charset === "iso-8859-1"
            ? (Y += "utf8=%26%2310003%3B&")
            : (Y += "utf8=%E2%9C%93&")),
        $.length > 0 ? Y + $ : ""
      );
    }),
    dt
  );
}
var ht, lo;
function ui() {
  if (lo) return ht;
  lo = 1;
  var e = Po(),
    t = Object.prototype.hasOwnProperty,
    r = Array.isArray,
    a = {
      allowDots: !1,
      allowEmptyArrays: !1,
      allowPrototypes: !1,
      allowSparse: !1,
      arrayLimit: 20,
      charset: "utf-8",
      charsetSentinel: !1,
      comma: !1,
      decodeDotInKeys: !1,
      decoder: e.decode,
      delimiter: "&",
      depth: 5,
      duplicates: "combine",
      ignoreQueryPrefix: !1,
      interpretNumericEntities: !1,
      parameterLimit: 1e3,
      parseArrays: !0,
      plainObjects: !1,
      strictDepth: !1,
      strictNullHandling: !1,
      throwOnLimitExceeded: !1,
    },
    m = function (g) {
      return g.replace(/&#(\d+);/g, function (p, b) {
        return String.fromCharCode(parseInt(b, 10));
      });
    },
    o = function (g, p, b) {
      if (g && typeof g == "string" && p.comma && g.indexOf(",") > -1)
        return g.split(",");
      if (p.throwOnLimitExceeded && b >= p.arrayLimit)
        throw new RangeError(
          "Array limit exceeded. Only " +
            p.arrayLimit +
            " element" +
            (p.arrayLimit === 1 ? "" : "s") +
            " allowed in an array.",
        );
      return g;
    },
    i = "utf8=%26%2310003%3B",
    n = "utf8=%E2%9C%93",
    v = function (p, b) {
      var E = { __proto__: null },
        l = b.ignoreQueryPrefix ? p.replace(/^\?/, "") : p;
      l = l.replace(/%5B/gi, "[").replace(/%5D/gi, "]");
      var d = b.parameterLimit === 1 / 0 ? void 0 : b.parameterLimit,
        s = l.split(b.delimiter, b.throwOnLimitExceeded ? d + 1 : d);
      if (b.throwOnLimitExceeded && s.length > d)
        throw new RangeError(
          "Parameter limit exceeded. Only " +
            d +
            " parameter" +
            (d === 1 ? "" : "s") +
            " allowed.",
        );
      var w = -1,
        S,
        R = b.charset;
      if (b.charsetSentinel)
        for (S = 0; S < s.length; ++S)
          s[S].indexOf("utf8=") === 0 &&
            (s[S] === n ? (R = "utf-8") : s[S] === i && (R = "iso-8859-1"),
            (w = S),
            (S = s.length));
      for (S = 0; S < s.length; ++S)
        if (S !== w) {
          var O = s[S],
            A = O.indexOf("]="),
            T = A === -1 ? O.indexOf("=") : A + 1,
            q,
            C;
          (T === -1
            ? ((q = b.decoder(O, a.decoder, R, "key")),
              (C = b.strictNullHandling ? null : ""))
            : ((q = b.decoder(O.slice(0, T), a.decoder, R, "key")),
              (C = e.maybeMap(
                o(O.slice(T + 1), b, r(E[q]) ? E[q].length : 0),
                function ($) {
                  return b.decoder($, a.decoder, R, "value");
                },
              ))),
            C &&
              b.interpretNumericEntities &&
              R === "iso-8859-1" &&
              (C = m(String(C))),
            O.indexOf("[]=") > -1 && (C = r(C) ? [C] : C));
          var B = t.call(E, q);
          B && b.duplicates === "combine"
            ? (E[q] = e.combine(E[q], C))
            : (!B || b.duplicates === "last") && (E[q] = C);
        }
      return E;
    },
    c = function (g, p, b, E) {
      var l = 0;
      if (g.length > 0 && g[g.length - 1] === "[]") {
        var d = g.slice(0, -1).join("");
        l = Array.isArray(p) && p[d] ? p[d].length : 0;
      }
      for (var s = E ? p : o(p, b, l), w = g.length - 1; w >= 0; --w) {
        var S,
          R = g[w];
        if (R === "[]" && b.parseArrays)
          S =
            b.allowEmptyArrays &&
            (s === "" || (b.strictNullHandling && s === null))
              ? []
              : e.combine([], s);
        else {
          S = b.plainObjects ? { __proto__: null } : {};
          var O =
              R.charAt(0) === "[" && R.charAt(R.length - 1) === "]"
                ? R.slice(1, -1)
                : R,
            A = b.decodeDotInKeys ? O.replace(/%2E/g, ".") : O,
            T = parseInt(A, 10);
          !b.parseArrays && A === ""
            ? (S = { 0: s })
            : !isNaN(T) &&
                R !== A &&
                String(T) === A &&
                T >= 0 &&
                b.parseArrays &&
                T <= b.arrayLimit
              ? ((S = []), (S[T] = s))
              : A !== "__proto__" && (S[A] = s);
        }
        s = S;
      }
      return s;
    },
    u = function (p, b, E, l) {
      if (p) {
        var d = E.allowDots ? p.replace(/\.([^.[]+)/g, "[$1]") : p,
          s = /(\[[^[\]]*])/,
          w = /(\[[^[\]]*])/g,
          S = E.depth > 0 && s.exec(d),
          R = S ? d.slice(0, S.index) : d,
          O = [];
        if (R) {
          if (
            !E.plainObjects &&
            t.call(Object.prototype, R) &&
            !E.allowPrototypes
          )
            return;
          O.push(R);
        }
        for (
          var A = 0;
          E.depth > 0 && (S = w.exec(d)) !== null && A < E.depth;
        ) {
          if (
            ((A += 1),
            !E.plainObjects &&
              t.call(Object.prototype, S[1].slice(1, -1)) &&
              !E.allowPrototypes)
          )
            return;
          O.push(S[1]);
        }
        if (S) {
          if (E.strictDepth === !0)
            throw new RangeError(
              "Input depth exceeded depth option of " +
                E.depth +
                " and strictDepth is true",
            );
          O.push("[" + d.slice(S.index) + "]");
        }
        return c(O, b, E, l);
      }
    },
    h = function (p) {
      if (!p) return a;
      if (
        typeof p.allowEmptyArrays < "u" &&
        typeof p.allowEmptyArrays != "boolean"
      )
        throw new TypeError(
          "`allowEmptyArrays` option can only be `true` or `false`, when provided",
        );
      if (
        typeof p.decodeDotInKeys < "u" &&
        typeof p.decodeDotInKeys != "boolean"
      )
        throw new TypeError(
          "`decodeDotInKeys` option can only be `true` or `false`, when provided",
        );
      if (
        p.decoder !== null &&
        typeof p.decoder < "u" &&
        typeof p.decoder != "function"
      )
        throw new TypeError("Decoder has to be a function.");
      if (
        typeof p.charset < "u" &&
        p.charset !== "utf-8" &&
        p.charset !== "iso-8859-1"
      )
        throw new TypeError(
          "The charset option must be either utf-8, iso-8859-1, or undefined",
        );
      if (
        typeof p.throwOnLimitExceeded < "u" &&
        typeof p.throwOnLimitExceeded != "boolean"
      )
        throw new TypeError("`throwOnLimitExceeded` option must be a boolean");
      var b = typeof p.charset > "u" ? a.charset : p.charset,
        E = typeof p.duplicates > "u" ? a.duplicates : p.duplicates;
      if (E !== "combine" && E !== "first" && E !== "last")
        throw new TypeError(
          "The duplicates option must be either combine, first, or last",
        );
      var l =
        typeof p.allowDots > "u"
          ? p.decodeDotInKeys === !0
            ? !0
            : a.allowDots
          : !!p.allowDots;
      return {
        allowDots: l,
        allowEmptyArrays:
          typeof p.allowEmptyArrays == "boolean"
            ? !!p.allowEmptyArrays
            : a.allowEmptyArrays,
        allowPrototypes:
          typeof p.allowPrototypes == "boolean"
            ? p.allowPrototypes
            : a.allowPrototypes,
        allowSparse:
          typeof p.allowSparse == "boolean" ? p.allowSparse : a.allowSparse,
        arrayLimit:
          typeof p.arrayLimit == "number" ? p.arrayLimit : a.arrayLimit,
        charset: b,
        charsetSentinel:
          typeof p.charsetSentinel == "boolean"
            ? p.charsetSentinel
            : a.charsetSentinel,
        comma: typeof p.comma == "boolean" ? p.comma : a.comma,
        decodeDotInKeys:
          typeof p.decodeDotInKeys == "boolean"
            ? p.decodeDotInKeys
            : a.decodeDotInKeys,
        decoder: typeof p.decoder == "function" ? p.decoder : a.decoder,
        delimiter:
          typeof p.delimiter == "string" || e.isRegExp(p.delimiter)
            ? p.delimiter
            : a.delimiter,
        depth:
          typeof p.depth == "number" || p.depth === !1 ? +p.depth : a.depth,
        duplicates: E,
        ignoreQueryPrefix: p.ignoreQueryPrefix === !0,
        interpretNumericEntities:
          typeof p.interpretNumericEntities == "boolean"
            ? p.interpretNumericEntities
            : a.interpretNumericEntities,
        parameterLimit:
          typeof p.parameterLimit == "number"
            ? p.parameterLimit
            : a.parameterLimit,
        parseArrays: p.parseArrays !== !1,
        plainObjects:
          typeof p.plainObjects == "boolean" ? p.plainObjects : a.plainObjects,
        strictDepth:
          typeof p.strictDepth == "boolean" ? !!p.strictDepth : a.strictDepth,
        strictNullHandling:
          typeof p.strictNullHandling == "boolean"
            ? p.strictNullHandling
            : a.strictNullHandling,
        throwOnLimitExceeded:
          typeof p.throwOnLimitExceeded == "boolean"
            ? p.throwOnLimitExceeded
            : !1,
      };
    };
  return (
    (ht = function (g, p) {
      var b = h(p);
      if (g === "" || g === null || typeof g > "u")
        return b.plainObjects ? { __proto__: null } : {};
      for (
        var E = typeof g == "string" ? v(g, b) : g,
          l = b.plainObjects ? { __proto__: null } : {},
          d = Object.keys(E),
          s = 0;
        s < d.length;
        ++s
      ) {
        var w = d[s],
          S = u(w, E[w], b, typeof g == "string");
        l = e.merge(l, S, b);
      }
      return b.allowSparse === !0 ? l : e.compact(l);
    }),
    ht
  );
}
var mt, fo;
function ci() {
  if (fo) return mt;
  fo = 1;
  var e = fi(),
    t = ui(),
    r = jt();
  return ((mt = { formats: r, parse: t, stringify: e }), mt);
}
var pi = ci();
const yi = Ve(pi);
var di = Ca;
function he() {
  ((this.protocol = null),
    (this.slashes = null),
    (this.auth = null),
    (this.host = null),
    (this.port = null),
    (this.hostname = null),
    (this.hash = null),
    (this.search = null),
    (this.query = null),
    (this.pathname = null),
    (this.path = null),
    (this.href = null));
}
var hi = /^([a-z0-9.+-]+:)/i,
  mi = /:[0-9]*$/,
  vi = /^(\/\/?(?!\/)[^?\s]*)(\?[^\s]*)?$/,
  gi = [
    "<",
    ">",
    '"',
    "`",
    " ",
    "\r",
    `
`,
    "	",
  ],
  bi = ["{", "}", "|", "\\", "^", "`"].concat(gi),
  At = ["'"].concat(bi),
  uo = ["%", "/", "?", ";", "#"].concat(At),
  co = ["/", "?", "#"],
  Ai = 255,
  po = /^[+a-z0-9A-Z_-]{0,63}$/,
  Si = /^([+a-z0-9A-Z_-]{0,63})(.*)$/,
  Ei = { javascript: !0, "javascript:": !0 },
  St = { javascript: !0, "javascript:": !0 },
  Ne = {
    http: !0,
    https: !0,
    ftp: !0,
    gopher: !0,
    file: !0,
    "http:": !0,
    "https:": !0,
    "ftp:": !0,
    "gopher:": !0,
    "file:": !0,
  },
  Et = yi;
function Be(e, t, r) {
  if (e && typeof e == "object" && e instanceof he) return e;
  var a = new he();
  return (a.parse(e, t, r), a);
}
he.prototype.parse = function (e, t, r) {
  if (typeof e != "string")
    throw new TypeError("Parameter 'url' must be a string, not " + typeof e);
  var a = e.indexOf("?"),
    m = a !== -1 && a < e.indexOf("#") ? "?" : "#",
    o = e.split(m),
    i = /\\/g;
  ((o[0] = o[0].replace(i, "/")), (e = o.join(m)));
  var n = e;
  if (((n = n.trim()), !r && e.split("#").length === 1)) {
    var v = vi.exec(n);
    if (v)
      return (
        (this.path = n),
        (this.href = n),
        (this.pathname = v[1]),
        v[2]
          ? ((this.search = v[2]),
            t
              ? (this.query = Et.parse(this.search.substr(1)))
              : (this.query = this.search.substr(1)))
          : t && ((this.search = ""), (this.query = {})),
        this
      );
  }
  var c = hi.exec(n);
  if (c) {
    c = c[0];
    var u = c.toLowerCase();
    ((this.protocol = u), (n = n.substr(c.length)));
  }
  if (r || c || n.match(/^\/\/[^@/]+@[^@/]+/)) {
    var h = n.substr(0, 2) === "//";
    h && !(c && St[c]) && ((n = n.substr(2)), (this.slashes = !0));
  }
  if (!St[c] && (h || (c && !Ne[c]))) {
    for (var g = -1, p = 0; p < co.length; p++) {
      var b = n.indexOf(co[p]);
      b !== -1 && (g === -1 || b < g) && (g = b);
    }
    var E, l;
    (g === -1 ? (l = n.lastIndexOf("@")) : (l = n.lastIndexOf("@", g)),
      l !== -1 &&
        ((E = n.slice(0, l)),
        (n = n.slice(l + 1)),
        (this.auth = decodeURIComponent(E))),
      (g = -1));
    for (var p = 0; p < uo.length; p++) {
      var b = n.indexOf(uo[p]);
      b !== -1 && (g === -1 || b < g) && (g = b);
    }
    (g === -1 && (g = n.length),
      (this.host = n.slice(0, g)),
      (n = n.slice(g)),
      this.parseHost(),
      (this.hostname = this.hostname || ""));
    var d =
      this.hostname[0] === "[" &&
      this.hostname[this.hostname.length - 1] === "]";
    if (!d)
      for (var s = this.hostname.split(/\./), p = 0, w = s.length; p < w; p++) {
        var S = s[p];
        if (S && !S.match(po)) {
          for (var R = "", O = 0, A = S.length; O < A; O++)
            S.charCodeAt(O) > 127 ? (R += "x") : (R += S[O]);
          if (!R.match(po)) {
            var T = s.slice(0, p),
              q = s.slice(p + 1),
              C = S.match(Si);
            (C && (T.push(C[1]), q.unshift(C[2])),
              q.length && (n = "/" + q.join(".") + n),
              (this.hostname = T.join(".")));
            break;
          }
        }
      }
    (this.hostname.length > Ai
      ? (this.hostname = "")
      : (this.hostname = this.hostname.toLowerCase()),
      d || (this.hostname = di.toASCII(this.hostname)));
    var B = this.port ? ":" + this.port : "",
      $ = this.hostname || "";
    ((this.host = $ + B),
      (this.href += this.host),
      d &&
        ((this.hostname = this.hostname.substr(1, this.hostname.length - 2)),
        n[0] !== "/" && (n = "/" + n)));
  }
  if (!Ei[u])
    for (var p = 0, w = At.length; p < w; p++) {
      var Y = At[p];
      if (n.indexOf(Y) !== -1) {
        var G = encodeURIComponent(Y);
        (G === Y && (G = escape(Y)), (n = n.split(Y).join(G)));
      }
    }
  var te = n.indexOf("#");
  te !== -1 && ((this.hash = n.substr(te)), (n = n.slice(0, te)));
  var ae = n.indexOf("?");
  if (
    (ae !== -1
      ? ((this.search = n.substr(ae)),
        (this.query = n.substr(ae + 1)),
        t && (this.query = Et.parse(this.query)),
        (n = n.slice(0, ae)))
      : t && ((this.search = ""), (this.query = {})),
    n && (this.pathname = n),
    Ne[u] && this.hostname && !this.pathname && (this.pathname = "/"),
    this.pathname || this.search)
  ) {
    var B = this.pathname || "",
      se = this.search || "";
    this.path = B + se;
  }
  return ((this.href = this.format()), this);
};
function wi(e) {
  return (
    typeof e == "string" && (e = Be(e)),
    e instanceof he ? e.format() : he.prototype.format.call(e)
  );
}
he.prototype.format = function () {
  var e = this.auth || "";
  e && ((e = encodeURIComponent(e)), (e = e.replace(/%3A/i, ":")), (e += "@"));
  var t = this.protocol || "",
    r = this.pathname || "",
    a = this.hash || "",
    m = !1,
    o = "";
  (this.host
    ? (m = e + this.host)
    : this.hostname &&
      ((m =
        e +
        (this.hostname.indexOf(":") === -1
          ? this.hostname
          : "[" + this.hostname + "]")),
      this.port && (m += ":" + this.port)),
    this.query &&
      typeof this.query == "object" &&
      Object.keys(this.query).length &&
      (o = Et.stringify(this.query, {
        arrayFormat: "repeat",
        addQueryPrefix: !1,
      })));
  var i = this.search || (o && "?" + o) || "";
  return (
    t && t.substr(-1) !== ":" && (t += ":"),
    this.slashes || ((!t || Ne[t]) && m !== !1)
      ? ((m = "//" + (m || "")), r && r.charAt(0) !== "/" && (r = "/" + r))
      : m || (m = ""),
    a && a.charAt(0) !== "#" && (a = "#" + a),
    i && i.charAt(0) !== "?" && (i = "?" + i),
    (r = r.replace(/[?#]/g, function (n) {
      return encodeURIComponent(n);
    })),
    (i = i.replace("#", "%23")),
    t + m + r + i + a
  );
};
function Pi(e, t) {
  return Be(e, !1, !0).resolve(t);
}
he.prototype.resolve = function (e) {
  return this.resolveObject(Be(e, !1, !0)).format();
};
function Oi(e, t) {
  return e ? Be(e, !1, !0).resolveObject(t) : t;
}
he.prototype.resolveObject = function (e) {
  if (typeof e == "string") {
    var t = new he();
    (t.parse(e, !1, !0), (e = t));
  }
  for (var r = new he(), a = Object.keys(this), m = 0; m < a.length; m++) {
    var o = a[m];
    r[o] = this[o];
  }
  if (((r.hash = e.hash), e.href === "")) return ((r.href = r.format()), r);
  if (e.slashes && !e.protocol) {
    for (var i = Object.keys(e), n = 0; n < i.length; n++) {
      var v = i[n];
      v !== "protocol" && (r[v] = e[v]);
    }
    return (
      Ne[r.protocol] &&
        r.hostname &&
        !r.pathname &&
        ((r.pathname = "/"), (r.path = r.pathname)),
      (r.href = r.format()),
      r
    );
  }
  if (e.protocol && e.protocol !== r.protocol) {
    if (!Ne[e.protocol]) {
      for (var c = Object.keys(e), u = 0; u < c.length; u++) {
        var h = c[u];
        r[h] = e[h];
      }
      return ((r.href = r.format()), r);
    }
    if (((r.protocol = e.protocol), !e.host && !St[e.protocol])) {
      for (
        var w = (e.pathname || "").split("/");
        w.length && !(e.host = w.shift());
      );
      (e.host || (e.host = ""),
        e.hostname || (e.hostname = ""),
        w[0] !== "" && w.unshift(""),
        w.length < 2 && w.unshift(""),
        (r.pathname = w.join("/")));
    } else r.pathname = e.pathname;
    if (
      ((r.search = e.search),
      (r.query = e.query),
      (r.host = e.host || ""),
      (r.auth = e.auth),
      (r.hostname = e.hostname || e.host),
      (r.port = e.port),
      r.pathname || r.search)
    ) {
      var g = r.pathname || "",
        p = r.search || "";
      r.path = g + p;
    }
    return ((r.slashes = r.slashes || e.slashes), (r.href = r.format()), r);
  }
  var b = r.pathname && r.pathname.charAt(0) === "/",
    E = e.host || (e.pathname && e.pathname.charAt(0) === "/"),
    l = E || b || (r.host && e.pathname),
    d = l,
    s = (r.pathname && r.pathname.split("/")) || [],
    w = (e.pathname && e.pathname.split("/")) || [],
    S = r.protocol && !Ne[r.protocol];
  if (
    (S &&
      ((r.hostname = ""),
      (r.port = null),
      r.host && (s[0] === "" ? (s[0] = r.host) : s.unshift(r.host)),
      (r.host = ""),
      e.protocol &&
        ((e.hostname = null),
        (e.port = null),
        e.host && (w[0] === "" ? (w[0] = e.host) : w.unshift(e.host)),
        (e.host = null)),
      (l = l && (w[0] === "" || s[0] === ""))),
    E)
  )
    ((r.host = e.host || e.host === "" ? e.host : r.host),
      (r.hostname = e.hostname || e.hostname === "" ? e.hostname : r.hostname),
      (r.search = e.search),
      (r.query = e.query),
      (s = w));
  else if (w.length)
    (s || (s = []),
      s.pop(),
      (s = s.concat(w)),
      (r.search = e.search),
      (r.query = e.query));
  else if (e.search != null) {
    if (S) {
      ((r.host = s.shift()), (r.hostname = r.host));
      var R = r.host && r.host.indexOf("@") > 0 ? r.host.split("@") : !1;
      R &&
        ((r.auth = R.shift()), (r.hostname = R.shift()), (r.host = r.hostname));
    }
    return (
      (r.search = e.search),
      (r.query = e.query),
      (r.pathname !== null || r.search !== null) &&
        (r.path = (r.pathname ? r.pathname : "") + (r.search ? r.search : "")),
      (r.href = r.format()),
      r
    );
  }
  if (!s.length)
    return (
      (r.pathname = null),
      r.search ? (r.path = "/" + r.search) : (r.path = null),
      (r.href = r.format()),
      r
    );
  for (
    var O = s.slice(-1)[0],
      A =
        ((r.host || e.host || s.length > 1) && (O === "." || O === "..")) ||
        O === "",
      T = 0,
      q = s.length;
    q >= 0;
    q--
  )
    ((O = s[q]),
      O === "."
        ? s.splice(q, 1)
        : O === ".."
          ? (s.splice(q, 1), T++)
          : T && (s.splice(q, 1), T--));
  if (!l && !d) for (; T--; T) s.unshift("..");
  (l && s[0] !== "" && (!s[0] || s[0].charAt(0) !== "/") && s.unshift(""),
    A && s.join("/").substr(-1) !== "/" && s.push(""));
  var C = s[0] === "" || (s[0] && s[0].charAt(0) === "/");
  if (S) {
    ((r.hostname = C ? "" : s.length ? s.shift() : ""), (r.host = r.hostname));
    var R = r.host && r.host.indexOf("@") > 0 ? r.host.split("@") : !1;
    R &&
      ((r.auth = R.shift()), (r.hostname = R.shift()), (r.host = r.hostname));
  }
  return (
    (l = l || (r.host && s.length)),
    l && !C && s.unshift(""),
    s.length > 0
      ? (r.pathname = s.join("/"))
      : ((r.pathname = null), (r.path = null)),
    (r.pathname !== null || r.search !== null) &&
      (r.path = (r.pathname ? r.pathname : "") + (r.search ? r.search : "")),
    (r.auth = e.auth || r.auth),
    (r.slashes = r.slashes || e.slashes),
    (r.href = r.format()),
    r
  );
};
he.prototype.parseHost = function () {
  var e = this.host,
    t = mi.exec(e);
  (t &&
    ((t = t[0]),
    t !== ":" && (this.port = t.substr(1)),
    (e = e.substr(0, e.length - t.length))),
    e && (this.hostname = e));
};
var Ri = Be,
  _i = Pi,
  Oo = Oi,
  Ii = wi,
  xi = he;
function $i(e, t) {
  for (var r = 0, a = e.length - 1; a >= 0; a--) {
    var m = e[a];
    m === "."
      ? e.splice(a, 1)
      : m === ".."
        ? (e.splice(a, 1), r++)
        : r && (e.splice(a, 1), r--);
  }
  if (t) for (; r--; r) e.unshift("..");
  return e;
}
function Ti() {
  for (var e = "", t = !1, r = arguments.length - 1; r >= -1 && !t; r--) {
    var a = r >= 0 ? arguments[r] : "/";
    if (typeof a != "string")
      throw new TypeError("Arguments to path.resolve must be strings");
    if (!a) continue;
    ((e = a + "/" + e), (t = a.charAt(0) === "/"));
  }
  return (
    (e = $i(
      Ni(e.split("/"), function (m) {
        return !!m;
      }),
      !t,
    ).join("/")),
    (t ? "/" : "") + e || "."
  );
}
function Ni(e, t) {
  if (e.filter) return e.filter(t);
  for (var r = [], a = 0; a < e.length; a++) t(e[a], a, e) && r.push(e[a]);
  return r;
}
var Ro = (function (e) {
    function t() {
      var a = this || self;
      return (delete e.prototype.__magic__, a);
    }
    if (typeof globalThis == "object") return globalThis;
    if (this) return t();
    e.defineProperty(e.prototype, "__magic__", { configurable: !0, get: t });
    var r = __magic__;
    return r;
  })(Object),
  Ci = Ii,
  _o = Ri,
  Io = _i,
  xo = xi,
  we = Ro.URL,
  $o = Ro.URLSearchParams,
  Fi = /%/g,
  ki = /\\/g,
  Di = /\n/g,
  Ui = /\r/g,
  qi = /\t/g,
  Mi = 47;
function ji(e) {
  var t = e ?? null;
  return !!(t !== null && t?.href && t?.origin);
}
function Bi(e) {
  if (e.hostname !== "")
    throw new TypeError(
      'File URL host must be "localhost" or empty on browser',
    );
  for (var t = e.pathname, r = 0; r < t.length; r++)
    if (t[r] === "%") {
      var a = t.codePointAt(r + 2) | 32;
      if (t[r + 1] === "2" && a === 102)
        throw new TypeError(
          "File URL path must not include encoded / characters",
        );
    }
  return decodeURIComponent(t);
}
function Gi(e) {
  return (
    e.includes("%") && (e = e.replace(Fi, "%25")),
    e.includes("\\") && (e = e.replace(ki, "%5C")),
    e.includes(`
`) && (e = e.replace(Di, "%0A")),
    e.includes("\r") && (e = e.replace(Ui, "%0D")),
    e.includes("	") && (e = e.replace(qi, "%09")),
    e
  );
}
var To = function (t) {
    if (typeof t > "u")
      throw new TypeError('The "domain" argument must be specified');
    return new we("http://" + t).hostname;
  },
  No = function (t) {
    if (typeof t > "u")
      throw new TypeError('The "domain" argument must be specified');
    return new we("http://" + t).hostname;
  },
  Co = function (t) {
    var r = new we("file://"),
      a = Ti(t),
      m = t.charCodeAt(t.length - 1);
    return (
      m === Mi && a[a.length - 1] !== "/" && (a += "/"),
      (r.pathname = Gi(a)),
      r
    );
  },
  Fo = function (t) {
    if (!ji(t) && typeof t != "string")
      throw new TypeError(
        'The "path" argument must be of type string or an instance of URL. Received type ' +
          typeof t +
          " (" +
          t +
          ")",
      );
    var r = new we(t);
    if (r.protocol !== "file:")
      throw new TypeError("The URL must be of scheme file");
    return Bi(r);
  },
  ko = function (t, r) {
    var a, m, o, i;
    if ((r === void 0 && (r = {}), !(t instanceof we))) return Ci(t);
    if (typeof r != "object" || r === null)
      throw new TypeError('The "options" argument must be of type object.');
    var n = (a = r.auth) != null ? a : !0,
      v = (m = r.fragment) != null ? m : !0,
      c = (o = r.search) != null ? o : !0;
    (i = r.unicode) != null;
    var u = new we(t.toString());
    return (
      n || ((u.username = ""), (u.password = "")),
      v || (u.hash = ""),
      c || (u.search = ""),
      u.toString()
    );
  },
  Li = {
    format: ko,
    parse: _o,
    resolve: Io,
    resolveObject: Oo,
    Url: xo,
    URL: we,
    URLSearchParams: $o,
    domainToASCII: To,
    domainToUnicode: No,
    pathToFileURL: Co,
    fileURLToPath: Fo,
  };
const Js = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      URL: we,
      URLSearchParams: $o,
      Url: xo,
      default: Li,
      domainToASCII: To,
      domainToUnicode: No,
      fileURLToPath: Fo,
      format: ko,
      parse: _o,
      pathToFileURL: Co,
      resolve: Io,
      resolveObject: Oo,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
var Do = { __dirname: "/opt/ci/builds/builder/automattic/beeper/desktop" },
  yo = {};
const Wi = !1,
  Uo = !0,
  zi = Uo,
  Hi = "config.json";
function qo() {
  return yo.BEEPER_USER_DATA_DIR
    ? yo.BEEPER_USER_DATA_DIR
    : qe.join(He.homedir(), "Library", "Application Support", "BeeperTexts");
}
function Mo() {
  const e = qo();
  return qe.join(e, Hi);
}
const Ki = Do?.userConfPath ?? Mo(),
  Fe = +He.release().split(".")[0],
  Vi = Fe >= 19,
  Ji = Fe >= 20,
  Qi = Fe >= 21,
  Yi = Fe >= 22,
  Bt = Fe >= 25,
  Zi = { x: Bt ? 12 : 18, y: 18 },
  Xi = { x: 8, y: Bt ? 18 : 8 },
  es = 140;
function rs() {
  return (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" +
    ` AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${es}.0.0.0 Safari/537.36`
  );
}
const jo = rs(),
  ts = "Beeper/3.110.1",
  ns = jo?.replace(/ Chrome\/\d+\.\d+\.\d+\.\d+/, ` ${ts}$&`),
  os = "beeper://",
  as =
    "<REDACTED_GOOGLE_OAUTH_CLIENT_ID>",
  is = "com.automattic.beeper.siwa",
  ss = "help@beeper.com",
  ls = "mailto:help+feedback@beeper.com",
  fs =
    "https://help.beeper.com/en_US/quick-references/how-to-create-and-manage-merged-chats",
  us =
    "https://help.beeper.com/using-on-device-chat-network-connections-in-beeper",
  Bo = "texts.com",
  Go = `https://${Bo}`,
  _e = "https://www.beeper.com",
  cs = `${_e}/terms-onboarding`,
  ps = `${_e}/privacy`,
  ys = `${_e}/`,
  ds = `${Go}/api/beeper`,
  Lo = "com.automattic.beeper.desktop",
  hs = "beeper-a8c-desktop",
  ms = "BEEPER-PRIVATE-API-PLEASE-DONT-USE",
  vs = `${_e}/download/android`,
  gs = `${_e}/download/ios`,
  bs = `${_e}/download`,
  As = "https://www.beeper.com/changelog/desktop",
  Wo = qe.join(Do.__dirname, typeof window > "u" ? ".." : ""),
  zo = Wo,
  Ss = zo.replace(`app.asar${qe.sep}`, `app.asar.unpacked${qe.sep}`),
  Es = "beeper_8a5da52ed126447d359e70c05721a8aa",
  ws = "!transcriptions:beeper.local",
  Ps = "@room",
  Os = [
    { id: "chatgpt", displayName: "ChatGPT", icon: "GPT" },
    { id: "apple-ai", displayName: "Apple Intelligence", icon: "APPLE" },
  ],
  Rs = {
    "gpt-5-mini": "GPT 5 mini",
    "gpt-5-nano": "GPT 5 nano",
    "gpt-4.1-mini": "GPT 4.1 mini",
  },
  _s = "gpt-4.1-mini",
  Is = 330,
  xs = 620,
  $s = 400,
  Ts = 505,
  Ns = "add-account",
  Cs = 400,
  Fs = 560,
  ks = 1200,
  Ds = 800,
  Us = [
    { id: "monochrome-red", name: "Red", hue: 0, type: "monochrome" },
    { id: "monochrome-green", name: "Green", hue: 120, type: "monochrome" },
    { id: "monochrome-blue", name: "Blue", hue: 210, type: "monochrome" },
    { id: "monochrome-purple", name: "Purple", hue: 270, type: "monochrome" },
    {
      id: "rich-red",
      name: "Rich Red",
      type: "rich",
      lightGradient: ["#FE9A9A", "#FECEA9"],
      darkGradient: ["#6A0303", "#3C0000"],
    },
    {
      id: "rich-green",
      name: "Rich Green",
      type: "rich",
      lightGradient: ["#80EA8B", "#EFFB81"],
      darkGradient: ["#4A6729", "#163D2C"],
    },
    {
      id: "rich-blue",
      name: "Rich Blue",
      type: "rich",
      lightGradient: ["#80CBEA", "#81FBAE"],
      darkGradient: ["#04409B", "#001B44"],
    },
    {
      id: "rich-purple",
      name: "Rich Purple",
      type: "rich",
      lightGradient: ["#C6A7F4", "#7EA1F9"],
      darkGradient: ["#6E16B2", "#400170"],
    },
    {
      id: "rich-grey",
      name: "Rich Grey",
      type: "rich",
      lightGradient: ["#F9F9F9", "#6E6E6E"],
      darkGradient: ["#454545", "#000000"],
    },
  ],
  qs = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2],
  Ms = [0, 30, 90, 120],
  Qs = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        ADD_ACCOUNTS_SCREEN_HEIGHT: Ts,
        ADD_ACCOUNTS_SCREEN_WIDTH: $s,
        ADD_ACCOUNTS_WINDOW_ID: Ns,
        AGE_DAYS: Ms,
        AI_ENGINES: Rs,
        ANDROID_DOWNLOAD_LINK: vs,
        API_ENDPOINT: ds,
        APPLE_SIGN_IN_SERVICES_ID: is,
        APP_SCREEN_HEIGHT: Ds,
        APP_SCREEN_WIDTH: ks,
        BEEPER_API_ACCOUNT_ID: Es,
        BEEPER_CHANGELOG_LINK: As,
        BEEPER_DOMAIN: _e,
        BEEPER_DOWNLOAD_LINK: bs,
        BEEPER_GUEST_TOKEN: ms,
        BRIDGE_TYPE_LEARN_MORE_LINK: us,
        BUILD_DIR_PATH: Wo,
        BUNDLE_ID: Lo,
        DEEP_LINK_PROTOCOL: os,
        DEFAULT_AI_ENGINE: _s,
        DEFAULT_PLAYBACK_RATES: qs,
        DOMAIN: Go,
        FEEDBACK_MAILTO: ls,
        GOOGLE_OAUTH_CLIENT_ID: as,
        GOOGLE_SAFE_USER_AGENT: ns,
        HOSTNAME: Bo,
        IOS_DOWNLOAD_LINK: gs,
        IS_BIG_SUR_OR_UP: Ji,
        IS_CATALINA_OR_UP: Vi,
        IS_MAC_OR_WINDOWS: zi,
        IS_MAC_OS: Uo,
        IS_MONTEREY_OR_UP: Qi,
        IS_TAHOE_OR_UP: Bt,
        IS_VENTURA_OR_UP: Yi,
        IS_WINDOWS: Wi,
        LLM_BOTS: Os,
        LOGIN_SCREEN_HEIGHT: Fs,
        LOGIN_SCREEN_WIDTH: Cs,
        MACOS_MAJOR_VERSION: Fe,
        MAC_RAIL_TRAFFIC_LIGHT_POSITION: Xi,
        MAC_TRAFFIC_LIGHT_POSITION: Zi,
        MERGED_CHATS_LEARN_MORE_LINK: fs,
        ONBOARDING_SCREEN_HEIGHT: xs,
        ONBOARDING_SCREEN_WIDTH: Is,
        PRIVACY_URL: ps,
        PUBLIC_DIR_PATH: zo,
        PUBLIC_DIR_PATH_UNPACKED: Ss,
        RAGESHAKE_APP_NAME: hs,
        ROOM_MENTION: Ps,
        SUPPORT_EMAIL: ss,
        TOS_ONBOARDING_URL: cs,
        TRANSCRIPTIONS_ROOM_ID: ws,
        UI_THEMES: Us,
        USER_AGENT: jo,
        USER_CONF_PATH: Ki,
        WEBSITE: ys,
        resolveUserConfPath: Mo,
        resolveUserDataDir: qo,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  Ys = Lo.endsWith(".nightly"),
  js = wt.developer_mode || !1;
var Bs = {};
const Gs = Bs.FORCE_SENTRY != null || (!js && !wt.sentry_disabled),
  { username: vt } = "userInfo" in He ? He.userInfo() : { username: "" },
  Ls = va({ strict: !0 }),
  $e = (e) => {
    if (!e || typeof e != "string") return e;
    const r = (vt && vt.length > 2 ? e.replaceAll?.(vt, "$USER") : e)
      .replace(Ls, "<scrubbed_url>")
      .replace(
        /(iMessage|SMS|RCS);[-+];(chat)?\+?[\d -]+/g,
        "<scrubbed_imsg_id>",
      )
      .replace(/\d+@s\.whatsapp\.net/g, "<scrubbed_wa_id>")
      .replace(/\+\d[\d ().-]{5,}\d/g, "<scrubbed_phone>");
    return Ao(r);
  },
  Ws = (e) =>
    e
      .replace(/(?:[A-Za-z]:\\|[/\\])[\s\S]*$/, "<path>")
      .replace(/\b\d+\b/g, "<n>")
      .trim()
      .slice(0, 120);
function zs(e) {
  return (
    e &&
    (e.exception?.values?.forEach((t) => {
      (t.stacktrace?.frames?.forEach((r) => {
        delete r.module;
      }),
        t?.value && (t.value = $e(t.value)));
    }),
    typeof e.message == "string" && (e.message = $e(e.message)),
    typeof e.logentry?.message == "string" &&
      (e.logentry.message = $e(e.logentry.message)),
    e.breadcrumbs?.forEach((t) => {
      !t?.message ||
        (t.type === "ui" && t.category === "electron" && t.level === "info") ||
        (t.message = $e(t.message));
    }),
    e)
  );
}
function Hs(e) {
  const { data: t } = e;
  if (!t) return e;
  const r = { data: { ...t }, ...e };
  for (const a of Object.keys(t))
    typeof t[a] == "string" && (r.data[a] = $e(t[a]));
  return r;
}
const Zs = {
  enabled: Gs,
  dsn: Aa,
  release: ba.version,
  environment: "production",
  tracesSampleRate: 1,
  tracePropagationTargets: [
    /^https?:\/\/(localhost|127\.0\.0\.1)/,
    /^fileproxy:\/\//,
    /^https:\/\/(api\.)?beeper(-staging|-dev)?\.com/,
    /^https:\/\/(m\.)?texts\.com/,
    /^\//,
  ],
  beforeBreadcrumb: Hs,
  beforeSend: (e, t) => {
    const r = zs(e),
      a = Ra(t?.originalException);
    if (r && a) {
      const m = $e(a.cause);
      ((r.fingerprint = [
        "{{ default }}",
        "sdk-error",
        a.tag,
        a.method,
        m,
      ].filter(Boolean)),
        (r.tags = {
          ...r.tags,
          sdk_method: a.method,
          sdk_cause: m,
          ...(a.tag && { sdk_call: a.tag }),
        }));
      for (const o of r.exception?.values ?? [])
        o.type === "SDKError"
          ? (o.type = `SDKError(${a.method})`)
          : o.type === "RelayedError" &&
            a.tag &&
            (o.type = `RelayedError(${a.tag})`);
    } else if (r) {
      const m = r.exception?.values?.find(
        (o) => o.type === "SqliteError" && o.value,
      );
      m?.value && (r.fingerprint = ["{{ default }}", "sqlite", Ws(m.value)]);
    }
    return r;
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
export {
  Us as $,
  Ts as A,
  Es as B,
  Ys as C,
  os as D,
  Bt as E,
  ls as F,
  as as G,
  Yi as H,
  gs as I,
  Wi as J,
  Fs as K,
  Os as L,
  Cs as M,
  Ks as N,
  Xi as O,
  Zi as P,
  fs as Q,
  xs as R,
  Is as S,
  ps as T,
  Ss as U,
  hs as V,
  Ps as W,
  Vs as X,
  ss as Y,
  cs as Z,
  ws as _,
  $s as a,
  jo as a0,
  Ki as a1,
  ys as a2,
  Li as a3,
  Ke as a4,
  Qs as a5,
  ua as a6,
  Ve as a7,
  He as a8,
  qe as a9,
  xa as aa,
  ba as ab,
  na as ac,
  bo as ad,
  Ia as ae,
  $e as af,
  Zs as ag,
  Sa as ah,
  Js as ai,
  wt as aj,
  Ns as b,
  Ms as c,
  Rs as d,
  vs as e,
  ds as f,
  is as g,
  Ds as h,
  ks as i,
  As as j,
  _e as k,
  bs as l,
  ms as m,
  us as n,
  Wo as o,
  Lo as p,
  _s as q,
  qs as r,
  Go as s,
  ns as t,
  Ji as u,
  Vi as v,
  js as w,
  zi as x,
  Uo as y,
  Qi as z,
};
//# sourceMappingURL=sentry-common-BNqrY_yc.js.map
