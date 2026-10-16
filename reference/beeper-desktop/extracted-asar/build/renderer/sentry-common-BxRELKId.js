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
      (e._sentryDebugIds[t] = "100b9141-1fcd-4430-836e-1d041d07f9de"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-100b9141-1fcd-4430-836e-1d041d07f9de"));
  } catch {}
})();
function Go(e) {
  return e && e.__esModule && Object.prototype.hasOwnProperty.call(e, "default")
    ? e.default
    : e;
}
var yo = { exports: {} },
  ie = (yo.exports = {}),
  me,
  ge;
function mt() {
  throw new Error("setTimeout has not been defined");
}
function gt() {
  throw new Error("clearTimeout has not been defined");
}
(function () {
  try {
    typeof setTimeout == "function" ? (me = setTimeout) : (me = mt);
  } catch {
    me = mt;
  }
  try {
    typeof clearTimeout == "function" ? (ge = clearTimeout) : (ge = gt);
  } catch {
    ge = gt;
  }
})();
function ho(e) {
  if (me === setTimeout) return setTimeout(e, 0);
  if ((me === mt || !me) && setTimeout)
    return ((me = setTimeout), setTimeout(e, 0));
  try {
    return me(e, 0);
  } catch {
    try {
      return me.call(null, e, 0);
    } catch {
      return me.call(this, e, 0);
    }
  }
}
function Lo(e) {
  if (ge === clearTimeout) return clearTimeout(e);
  if ((ge === gt || !ge) && clearTimeout)
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
  xe = !1,
  Re,
  Ge = -1;
function Wo() {
  !xe ||
    !Re ||
    ((xe = !1),
    Re.length ? (be = Re.concat(be)) : (Ge = -1),
    be.length && vo());
}
function vo() {
  if (!xe) {
    var e = ho(Wo);
    xe = !0;
    for (var t = be.length; t;) {
      for (Re = be, be = []; ++Ge < t;) Re && Re[Ge].run();
      ((Ge = -1), (t = be.length));
    }
    ((Re = null), (xe = !1), Lo(e));
  }
}
ie.nextTick = function (e) {
  var t = new Array(arguments.length - 1);
  if (arguments.length > 1)
    for (var r = 1; r < arguments.length; r++) t[r - 1] = arguments[r];
  (be.push(new mo(e, t)), be.length === 1 && !xe && ho(vo));
};
function mo(e, t) {
  ((this.fun = e), (this.array = t));
}
mo.prototype.run = function () {
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
var zo = yo.exports;
const Ho = Go(zo),
  Zi = globalThis.MACHINE_ID,
  Ko = () => "/tmp",
  Vo = () => globalThis.INITIAL_STATE.os_userInfo,
  Jo = () => globalThis.INITIAL_STATE.os_release,
  Qo = () => globalThis.INITIAL_STATE.os_arch,
  Yo = () => globalThis.INITIAL_STATE.os_platform,
  Zo = () => globalThis.INITIAL_STATE.os_homedir,
  Le = {
    tmpdir: Ko,
    homedir: Zo,
    platform: Yo,
    arch: Qo,
    release: Jo,
    userInfo: Vo,
  };
var We =
  typeof globalThis < "u"
    ? globalThis
    : typeof window < "u"
      ? window
      : typeof global < "u"
        ? global
        : typeof self < "u"
          ? self
          : {};
function He(e) {
  return e && e.__esModule && Object.prototype.hasOwnProperty.call(e, "default")
    ? e.default
    : e;
}
function Xo(e) {
  if (Object.prototype.hasOwnProperty.call(e, "__esModule")) return e;
  var t = e.default;
  if (typeof t == "function") {
    var r = function a() {
      var v = !1;
      try {
        v = this instanceof a;
      } catch {}
      return v
        ? Reflect.construct(t, arguments, this.constructor)
        : t.apply(this, arguments);
    };
    r.prototype = t.prototype;
  } else r = {};
  return (
    Object.defineProperty(r, "__esModule", { value: !0 }),
    Object.keys(e).forEach(function (a) {
      var v = Object.getOwnPropertyDescriptor(e, a);
      Object.defineProperty(
        r,
        a,
        v.get
          ? v
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
var sr, Yt;
function ea() {
  if (Yt) return sr;
  Yt = 1;
  const e = "[a-fA-F\\d:]",
    t = (c) =>
      c && c.includeBoundaries
        ? `(?:(?<=\\s|^)(?=${e})|(?<=${e})(?=\\s|$))`
        : "",
    r =
      "(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]\\d|\\d)(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]\\d|\\d)){3}",
    a = "[a-fA-F\\d]{1,4}",
    v = `
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
    o = new RegExp(`(?:^${r}$)|(?:^${v}$)`),
    i = new RegExp(`^${r}$`),
    n = new RegExp(`^${v}$`),
    m = (c) =>
      c && c.exact
        ? o
        : new RegExp(`(?:${t(c)}${r}${t(c)})|(?:${t(c)}${v}${t(c)})`, "g");
  return (
    (m.v4 = (c) => (c && c.exact ? i : new RegExp(`${t(c)}${r}${t(c)}`, "g"))),
    (m.v6 = (c) => (c && c.exact ? n : new RegExp(`${t(c)}${v}${t(c)}`, "g"))),
    (sr = m),
    sr
  );
}
const ra = JSON.parse(
    '["aaa","aarp","abb","abbott","abbvie","abc","able","abogado","abudhabi","ac","academy","accenture","accountant","accountants","aco","actor","ad","ads","adult","ae","aeg","aero","aetna","af","afl","africa","ag","agakhan","agency","ai","aig","airbus","airforce","airtel","akdn","al","alibaba","alipay","allfinanz","allstate","ally","alsace","alstom","am","amazon","americanexpress","americanfamily","amex","amfam","amica","amsterdam","analytics","android","anquan","anz","ao","aol","apartments","app","apple","aq","aquarelle","ar","arab","aramco","archi","army","arpa","art","arte","as","asda","asia","associates","at","athleta","attorney","au","auction","audi","audible","audio","auspost","author","auto","autos","aw","aws","ax","axa","az","azure","ba","baby","baidu","banamex","band","bank","bar","barcelona","barclaycard","barclays","barefoot","bargains","baseball","basketball","bauhaus","bayern","bb","bbc","bbt","bbva","bcg","bcn","bd","be","beats","beauty","beer","bentley","berlin","best","bestbuy","bet","bf","bg","bh","bharti","bi","bible","bid","bike","bing","bingo","bio","biz","bj","black","blackfriday","blockbuster","blog","bloomberg","blue","bm","bms","bmw","bn","bnpparibas","bo","boats","boehringer","bofa","bom","bond","boo","book","booking","bosch","bostik","boston","bot","boutique","box","br","bradesco","bridgestone","broadway","broker","brother","brussels","bs","bt","build","builders","business","buy","buzz","bv","bw","by","bz","bzh","ca","cab","cafe","cal","call","calvinklein","cam","camera","camp","canon","capetown","capital","capitalone","car","caravan","cards","care","career","careers","cars","casa","case","cash","casino","cat","catering","catholic","cba","cbn","cbre","cc","cd","center","ceo","cern","cf","cfa","cfd","cg","ch","chanel","channel","charity","chase","chat","cheap","chintai","christmas","chrome","church","ci","cipriani","circle","cisco","citadel","citi","citic","city","ck","cl","claims","cleaning","click","clinic","clinique","clothing","cloud","club","clubmed","cm","cn","co","coach","codes","coffee","college","cologne","com","commbank","community","company","compare","computer","comsec","condos","construction","consulting","contact","contractors","cooking","cool","coop","corsica","country","coupon","coupons","courses","cpa","cr","credit","creditcard","creditunion","cricket","crown","crs","cruise","cruises","cu","cuisinella","cv","cw","cx","cy","cymru","cyou","cz","dad","dance","data","date","dating","datsun","day","dclk","dds","de","deal","dealer","deals","degree","delivery","dell","deloitte","delta","democrat","dental","dentist","desi","design","dev","dhl","diamonds","diet","digital","direct","directory","discount","discover","dish","diy","dj","dk","dm","dnp","do","docs","doctor","dog","domains","dot","download","drive","dtv","dubai","dunlop","dupont","durban","dvag","dvr","dz","earth","eat","ec","eco","edeka","edu","education","ee","eg","email","emerck","energy","engineer","engineering","enterprises","epson","equipment","er","ericsson","erni","es","esq","estate","et","eu","eurovision","eus","events","exchange","expert","exposed","express","extraspace","fage","fail","fairwinds","faith","family","fan","fans","farm","farmers","fashion","fast","fedex","feedback","ferrari","ferrero","fi","fidelity","fido","film","final","finance","financial","fire","firestone","firmdale","fish","fishing","fit","fitness","fj","fk","flickr","flights","flir","florist","flowers","fly","fm","fo","foo","food","football","ford","forex","forsale","forum","foundation","fox","fr","free","fresenius","frl","frogans","frontier","ftr","fujitsu","fun","fund","furniture","futbol","fyi","ga","gal","gallery","gallo","gallup","game","games","gap","garden","gay","gb","gbiz","gd","gdn","ge","gea","gent","genting","george","gf","gg","ggee","gh","gi","gift","gifts","gives","giving","gl","glass","gle","global","globo","gm","gmail","gmbh","gmo","gmx","gn","godaddy","gold","goldpoint","golf","goo","goodyear","goog","google","gop","got","gov","gp","gq","gr","grainger","graphics","gratis","green","gripe","grocery","group","gs","gt","gu","gucci","guge","guide","guitars","guru","gw","gy","hair","hamburg","hangout","haus","hbo","hdfc","hdfcbank","health","healthcare","help","helsinki","here","hermes","hiphop","hisamitsu","hitachi","hiv","hk","hkt","hm","hn","hockey","holdings","holiday","homedepot","homegoods","homes","homesense","honda","horse","hospital","host","hosting","hot","hotels","hotmail","house","how","hr","hsbc","ht","hu","hughes","hyatt","hyundai","ibm","icbc","ice","icu","id","ie","ieee","ifm","ikano","il","im","imamat","imdb","immo","immobilien","in","inc","industries","infiniti","info","ing","ink","institute","insurance","insure","int","international","intuit","investments","io","ipiranga","iq","ir","irish","is","ismaili","ist","istanbul","it","itau","itv","jaguar","java","jcb","je","jeep","jetzt","jewelry","jio","jll","jm","jmp","jnj","jo","jobs","joburg","jot","joy","jp","jpmorgan","jprs","juegos","juniper","kaufen","kddi","ke","kerryhotels","kerrylogistics","kerryproperties","kfh","kg","kh","ki","kia","kids","kim","kindle","kitchen","kiwi","km","kn","koeln","komatsu","kosher","kp","kpmg","kpn","kr","krd","kred","kuokgroup","kw","ky","kyoto","kz","la","lacaixa","lamborghini","lamer","lancaster","land","landrover","lanxess","lasalle","lat","latino","latrobe","law","lawyer","lb","lc","lds","lease","leclerc","lefrak","legal","lego","lexus","lgbt","li","lidl","life","lifeinsurance","lifestyle","lighting","like","lilly","limited","limo","lincoln","link","lipsy","live","living","lk","llc","llp","loan","loans","locker","locus","lol","london","lotte","lotto","love","lpl","lplfinancial","lr","ls","lt","ltd","ltda","lu","lundbeck","luxe","luxury","lv","ly","ma","madrid","maif","maison","makeup","man","management","mango","map","market","marketing","markets","marriott","marshalls","mattel","mba","mc","mckinsey","md","me","med","media","meet","melbourne","meme","memorial","men","menu","merckmsd","mg","mh","miami","microsoft","mil","mini","mint","mit","mitsubishi","mk","ml","mlb","mls","mm","mma","mn","mo","mobi","mobile","moda","moe","moi","mom","monash","money","monster","mormon","mortgage","moscow","moto","motorcycles","mov","movie","mp","mq","mr","ms","msd","mt","mtn","mtr","mu","museum","music","mv","mw","mx","my","mz","na","nab","nagoya","name","navy","nba","nc","ne","nec","net","netbank","netflix","network","neustar","new","news","next","nextdirect","nexus","nf","nfl","ng","ngo","nhk","ni","nico","nike","nikon","ninja","nissan","nissay","nl","no","nokia","norton","now","nowruz","nowtv","np","nr","nra","nrw","ntt","nu","nyc","nz","obi","observer","office","okinawa","olayan","olayangroup","ollo","om","omega","one","ong","onl","online","ooo","open","oracle","orange","org","organic","origins","osaka","otsuka","ott","ovh","pa","page","panasonic","paris","pars","partners","parts","party","pay","pccw","pe","pet","pf","pfizer","pg","ph","pharmacy","phd","philips","phone","photo","photography","photos","physio","pics","pictet","pictures","pid","pin","ping","pink","pioneer","pizza","pk","pl","place","play","playstation","plumbing","plus","pm","pn","pnc","pohl","poker","politie","porn","post","pr","pramerica","praxi","press","prime","pro","prod","productions","prof","progressive","promo","properties","property","protection","pru","prudential","ps","pt","pub","pw","pwc","py","qa","qpon","quebec","quest","racing","radio","re","read","realestate","realtor","realty","recipes","red","redstone","redumbrella","rehab","reise","reisen","reit","reliance","ren","rent","rentals","repair","report","republican","rest","restaurant","review","reviews","rexroth","rich","richardli","ricoh","ril","rio","rip","ro","rocks","rodeo","rogers","room","rs","rsvp","ru","rugby","ruhr","run","rw","rwe","ryukyu","sa","saarland","safe","safety","sakura","sale","salon","samsclub","samsung","sandvik","sandvikcoromant","sanofi","sap","sarl","sas","save","saxo","sb","sbi","sbs","sc","scb","schaeffler","schmidt","scholarships","school","schule","schwarz","science","scot","sd","se","search","seat","secure","security","seek","select","sener","services","seven","sew","sex","sexy","sfr","sg","sh","shangrila","sharp","shell","shia","shiksha","shoes","shop","shopping","shouji","show","si","silk","sina","singles","site","sj","sk","ski","skin","sky","skype","sl","sling","sm","smart","smile","sn","sncf","so","soccer","social","softbank","software","sohu","solar","solutions","song","sony","soy","spa","space","sport","spot","sr","srl","ss","st","stada","staples","star","statebank","statefarm","stc","stcgroup","stockholm","storage","store","stream","studio","study","style","su","sucks","supplies","supply","support","surf","surgery","suzuki","sv","swatch","swiss","sx","sy","sydney","systems","sz","tab","taipei","talk","taobao","target","tatamotors","tatar","tattoo","tax","taxi","tc","tci","td","tdk","team","tech","technology","tel","temasek","tennis","teva","tf","tg","th","thd","theater","theatre","tiaa","tickets","tienda","tips","tires","tirol","tj","tjmaxx","tjx","tk","tkmaxx","tl","tm","tmall","tn","to","today","tokyo","tools","top","toray","toshiba","total","tours","town","toyota","toys","tr","trade","trading","training","travel","travelers","travelersinsurance","trust","trv","tt","tube","tui","tunes","tushu","tv","tvs","tw","tz","ua","ubank","ubs","ug","uk","unicom","university","uno","uol","ups","us","uy","uz","va","vacations","vana","vanguard","vc","ve","vegas","ventures","verisign","vermögensberater","vermögensberatung","versicherung","vet","vg","vi","viajes","video","vig","viking","villas","vin","vip","virgin","visa","vision","viva","vivo","vlaanderen","vn","vodka","volvo","vote","voting","voto","voyage","vu","wales","walmart","walter","wang","wanggou","watch","watches","weather","weatherchannel","webcam","weber","website","wed","wedding","weibo","weir","wf","whoswho","wien","wiki","williamhill","win","windows","wine","winners","wme","wolterskluwer","woodside","work","works","world","wow","ws","wtc","wtf","xbox","xerox","xihuan","xin","xxx","xyz","yachts","yahoo","yamaxun","yandex","ye","yodobashi","yoga","yokohama","you","youtube","yt","yun","za","zappos","zara","zero","zip","zm","zone","zuerich","zw","ελ","ευ","бг","бел","дети","ею","католик","ком","мкд","мон","москва","онлайн","орг","рус","рф","сайт","срб","укр","қаз","հայ","ישראל","קום","ابوظبي","ارامكو","الاردن","البحرين","الجزائر","السعودية","العليان","المغرب","امارات","ایران","بارت","بازار","بيتك","بھارت","تونس","سودان","سورية","شبكة","عراق","عرب","عمان","فلسطين","قطر","كاثوليك","كوم","مصر","مليسيا","موريتانيا","موقع","همراه","پاکستان","ڀارت","कॉम","नेट","भारत","भारतम्","भारोत","संगठन","বাংলা","ভারত","ভাৰত","ਭਾਰਤ","ભારત","ଭାରତ","இந்தியா","இலங்கை","சிங்கப்பூர்","భారత్","ಭಾರತ","ഭാരതം","ලංකා","คอม","ไทย","ລາວ","გე","みんな","アマゾン","クラウド","グーグル","コム","ストア","セール","ファッション","ポイント","世界","中信","中国","中國","中文网","亚马逊","企业","佛山","信息","健康","八卦","公司","公益","台湾","台灣","商城","商店","商标","嘉里","嘉里大酒店","在线","大拿","天主教","娱乐","家電","广东","微博","慈善","我爱你","手机","招聘","政务","政府","新加坡","新闻","时尚","書籍","机构","淡马锡","游戏","澳門","点看","移动","组织机构","网址","网店","网站","网络","联通","谷歌","购物","通販","集团","電訊盈科","飞利浦","食品","餐厅","香格里拉","香港","닷넷","닷컴","삼성","한국"]',
  ),
  ta = {},
  na = Object.freeze(
    Object.defineProperty(
      { __proto__: null, default: ta },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  go = Xo(na);
var lr, Zt;
function oa() {
  if (Zt) return lr;
  Zt = 1;
  const e = ea(),
    t = ra,
    r = e.v4().source,
    a = e.v6().source,
    v = "(?:(?:[a-z\\u00a1-\\uffff0-9][-_]*)*[a-z\\u00a1-\\uffff0-9]+)",
    o = "(?:\\.(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)*",
    i = "(?:[a-z\\u00a1-\\uffff]{2,})",
    n = `(?:${t.sort((h, g) => g.length - h.length).join("|")})`,
    m = "(?::\\d{2,5})?";
  let c, u;
  return (
    (lr = (h) => {
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
                  return ((c = go), typeof c == "function" ? c : RegExp);
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
        (s += `${v}${o}${E})${m}${d}`),
        h.returnString ? s : h.exact ? new g(`(?:^${s}$)`, "i") : new g(s, "ig")
      );
    }),
    lr
  );
}
var aa = oa();
const ia = He(aa),
  sa = "4.3.209",
  la = { version: sa },
  fa =
    "https://22069267152d0556896061c5c67463fc@o248881.ingest.us.sentry.io/4510439832551424",
  ua = (e) =>
    e
      .replace(/^\([^)]*\): \w+: /, "")
      .replace(/^\w+ failed: /, "")
      .replace(/^COM\.BEEPER\.[A-Z_]+(?: \(HTTP \d+\))?: /, ""),
  Xt = /^(\w+) failed: /,
  ca = /^\(([^)]*)\): /,
  pa = /\b((?:M_|COM\.BEEPER\.|FI\.MAU\.|NET\.MAUNIUM\.)[A-Z0-9_.]+)/,
  bo = (e) =>
    e
      .replace(/[!#][^\s:]+:[^\s,)]+/g, "<roomid>")
      .replace(/@[^\s:]+:[^\s,)]+/g, "<userid>")
      .replace(/\$[A-Za-z0-9_-]{8,}(?::[^\s,)]+)?/g, "<eventid>"),
  ya = (e) =>
    bo(ua(e))
      .replace(/\b[0-9a-f]{8,}\b/gi, "<hex>")
      .replace(/(?<!HTTP )\b\d+\b/g, "<n>")
      .trim()
      .slice(0, 120),
  da = (e) => {
    if (e.name !== "RelayedError") return { inner: e };
    const t = e.tag || ca.exec(e.message ?? "")?.[1],
      r = e.cause;
    return {
      tag: t && t !== "?" ? t : void 0,
      inner: r && typeof r == "object" ? r : e,
    };
  },
  ha = (e) => {
    const t = e;
    if (!t || typeof t != "object") return;
    const { tag: r, inner: a } = da(t),
      v = typeof a.message == "string" ? a.message : "",
      o =
        a.name === "SDKError" ||
        typeof a.internalError == "string" ||
        Xt.test(v);
    if (!o && !r) return;
    const i =
        a.methodName || Xt.exec(v)?.[1] || (o ? "unknown" : a.name || "Error"),
      n = pa.exec(`${a.internalError ?? ""}
${v}`)?.[1];
    return { tag: r, method: i, cause: n ?? ya(v) };
  },
  Et = globalThis.INITIAL_STATE.userConf,
  Xi = Et.hw_acceleration ?? !0,
  es = !1;
var fr, en;
function va() {
  if (en) return fr;
  en = 1;
  function e(v) {
    if (typeof v != "string")
      throw new TypeError(
        "Path must be a string. Received " + JSON.stringify(v),
      );
  }
  function t(v, o) {
    for (var i = "", n = 0, m = -1, c = 0, u, h = 0; h <= v.length; ++h) {
      if (h < v.length) u = v.charCodeAt(h);
      else {
        if (u === 47) break;
        u = 47;
      }
      if (u === 47) {
        if (!(m === h - 1 || c === 1))
          if (m !== h - 1 && c === 2) {
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
                    (m = h),
                    (c = 0));
                  continue;
                }
              } else if (i.length === 2 || i.length === 1) {
                ((i = ""), (n = 0), (m = h), (c = 0));
                continue;
              }
            }
            o && (i.length > 0 ? (i += "/..") : (i = ".."), (n = 2));
          } else
            (i.length > 0
              ? (i += "/" + v.slice(m + 1, h))
              : (i = v.slice(m + 1, h)),
              (n = h - m - 1));
        ((m = h), (c = 0));
      } else u === 46 && c !== -1 ? ++c : (c = -1);
    }
    return i;
  }
  function r(v, o) {
    var i = o.dir || o.root,
      n = o.base || (o.name || "") + (o.ext || "");
    return i ? (i === o.root ? i + n : i + v + n) : n;
  }
  var a = {
    resolve: function () {
      for (
        var o = "", i = !1, n, m = arguments.length - 1;
        m >= -1 && !i;
        m--
      ) {
        var c;
        (m >= 0
          ? (c = arguments[m])
          : (n === void 0 && (n = Ho.cwd()), (c = n)),
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
        var m = o.length, c = m - n, u = 1;
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
      for (E = n + b + 1; E <= m; ++E)
        (E === m || o.charCodeAt(E) === 47) &&
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
        var i = o.charCodeAt(0), n = i === 47, m = -1, c = !0, u = o.length - 1;
        u >= 1;
        --u
      )
        if (((i = o.charCodeAt(u)), i === 47)) {
          if (!c) {
            m = u;
            break;
          }
        } else c = !1;
      return m === -1 ? (n ? "/" : ".") : n && m === 1 ? "//" : o.slice(0, m);
    },
    basename: function (o, i) {
      if (i !== void 0 && typeof i != "string")
        throw new TypeError('"ext" argument must be a string');
      e(o);
      var n = 0,
        m = -1,
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
                  ? --h === -1 && (m = u)
                  : ((h = -1), (m = g))));
        }
        return (n === m ? (m = g) : m === -1 && (m = o.length), o.slice(n, m));
      } else {
        for (u = o.length - 1; u >= 0; --u)
          if (o.charCodeAt(u) === 47) {
            if (!c) {
              n = u + 1;
              break;
            }
          } else m === -1 && ((c = !1), (m = u + 1));
        return m === -1 ? "" : o.slice(n, m);
      }
    },
    extname: function (o) {
      e(o);
      for (
        var i = -1, n = 0, m = -1, c = !0, u = 0, h = o.length - 1;
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
        (m === -1 && ((c = !1), (m = h + 1)),
          g === 46
            ? i === -1
              ? (i = h)
              : u !== 1 && (u = 1)
            : i !== -1 && (u = -1));
      }
      return i === -1 ||
        m === -1 ||
        u === 0 ||
        (u === 1 && i === m - 1 && i === n + 1)
        ? ""
        : o.slice(i, m);
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
        m = n === 47,
        c;
      m ? ((i.root = "/"), (c = 1)) : (c = 0);
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
            (h === 0 && m
              ? (i.base = i.name = o.slice(1, g))
              : (i.base = i.name = o.slice(h, g)))
          : (h === 0 && m
              ? ((i.name = o.slice(1, u)), (i.base = o.slice(1, g)))
              : ((i.name = o.slice(h, u)), (i.base = o.slice(h, g))),
            (i.ext = o.slice(u, g))),
        h > 0 ? (i.dir = o.slice(0, h - 1)) : m && (i.dir = "/"),
        i
      );
    },
    sep: "/",
    delimiter: ":",
    win32: null,
    posix: null,
  };
  return ((a.posix = a), (fr = a), fr);
}
var ma = va();
const ze = He(ma);
var De = { exports: {} };
var ga = De.exports,
  rn;
function ba() {
  return (
    rn ||
      ((rn = 1),
      (function (e, t) {
        (function (r) {
          var a = t && !t.nodeType && t,
            v = e && !e.nodeType && e,
            o = typeof We == "object" && We;
          (o.global === o || o.window === o || o.self === o) && (r = o);
          var i,
            n = 2147483647,
            m = 36,
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
            S = m - c,
            R = Math.floor,
            O = String.fromCharCode,
            A;
          function $(T) {
            throw new RangeError(w[T]);
          }
          function q(T, F) {
            for (var B = T.length, L = []; B--;) L[B] = F(T[B]);
            return L;
          }
          function C(T, F) {
            var B = T.split("@"),
              L = "";
            (B.length > 1 && ((L = B[0] + "@"), (T = B[1])),
              (T = T.replace(s, ".")));
            var z = T.split("."),
              Q = q(z, F).join(".");
            return L + Q;
          }
          function j(T) {
            for (var F = [], B = 0, L = T.length, z, Q; B < L;)
              ((z = T.charCodeAt(B++)),
                z >= 55296 && z <= 56319 && B < L
                  ? ((Q = T.charCodeAt(B++)),
                    (Q & 64512) == 56320
                      ? F.push(((z & 1023) << 10) + (Q & 1023) + 65536)
                      : (F.push(z), B--))
                  : F.push(z));
            return F;
          }
          function x(T) {
            return q(T, function (F) {
              var B = "";
              return (
                F > 65535 &&
                  ((F -= 65536),
                  (B += O(((F >>> 10) & 1023) | 55296)),
                  (F = 56320 | (F & 1023))),
                (B += O(F)),
                B
              );
            }).join("");
          }
          function Y(T) {
            return T - 48 < 10
              ? T - 22
              : T - 65 < 26
                ? T - 65
                : T - 97 < 26
                  ? T - 97
                  : m;
          }
          function G(T, F) {
            return T + 22 + 75 * (T < 26) - ((F != 0) << 5);
          }
          function te(T, F, B) {
            var L = 0;
            for (
              T = B ? R(T / g) : T >> 1, T += R(T / F);
              T > (S * u) >> 1;
              L += m
            )
              T = R(T / S);
            return R(L + ((S + 1) * T) / (T + h));
          }
          function ae(T) {
            var F = [],
              B = T.length,
              L,
              z = 0,
              Q = b,
              H = p,
              Z,
              ne,
              D,
              P,
              _,
              I,
              N,
              M,
              K;
            for (Z = T.lastIndexOf(E), Z < 0 && (Z = 0), ne = 0; ne < Z; ++ne)
              (T.charCodeAt(ne) >= 128 && $("not-basic"),
                F.push(T.charCodeAt(ne)));
            for (D = Z > 0 ? Z + 1 : 0; D < B;) {
              for (
                P = z, _ = 1, I = m;
                D >= B && $("invalid-input"),
                  (N = Y(T.charCodeAt(D++))),
                  (N >= m || N > R((n - z) / _)) && $("overflow"),
                  (z += N * _),
                  (M = I <= H ? c : I >= H + u ? u : I - H),
                  !(N < M);
                I += m
              )
                ((K = m - M), _ > R(n / K) && $("overflow"), (_ *= K));
              ((L = F.length + 1),
                (H = te(z - P, L, P == 0)),
                R(z / L) > n - Q && $("overflow"),
                (Q += R(z / L)),
                (z %= L),
                F.splice(z++, 0, Q));
            }
            return x(F);
          }
          function se(T) {
            var F,
              B,
              L,
              z,
              Q,
              H,
              Z,
              ne,
              D,
              P,
              _,
              I = [],
              N,
              M,
              K,
              U;
            for (T = j(T), N = T.length, F = b, B = 0, Q = p, H = 0; H < N; ++H)
              ((_ = T[H]), _ < 128 && I.push(O(_)));
            for (L = z = I.length, z && I.push(E); L < N;) {
              for (Z = n, H = 0; H < N; ++H)
                ((_ = T[H]), _ >= F && _ < Z && (Z = _));
              for (
                M = L + 1,
                  Z - F > R((n - B) / M) && $("overflow"),
                  B += (Z - F) * M,
                  F = Z,
                  H = 0;
                H < N;
                ++H
              )
                if (((_ = T[H]), _ < F && ++B > n && $("overflow"), _ == F)) {
                  for (
                    ne = B, D = m;
                    (P = D <= Q ? c : D >= Q + u ? u : D - Q), !(ne < P);
                    D += m
                  )
                    ((U = ne - P),
                      (K = m - P),
                      I.push(O(G(P + (U % K), 0))),
                      (ne = R(U / K)));
                  (I.push(O(G(ne, 0))), (Q = te(B, M, L == z)), (B = 0), ++L);
                }
              (++B, ++F);
            }
            return I.join("");
          }
          function k(T) {
            return C(T, function (F) {
              return l.test(F) ? ae(F.slice(4).toLowerCase()) : F;
            });
          }
          function ee(T) {
            return C(T, function (F) {
              return d.test(F) ? "xn--" + se(F) : F;
            });
          }
          if (
            ((i = {
              version: "1.4.1",
              ucs2: { decode: j, encode: x },
              decode: ae,
              encode: se,
              toASCII: ee,
              toUnicode: k,
            }),
            a && v)
          )
            if (e.exports == a) v.exports = i;
            else for (A in i) i.hasOwnProperty(A) && (a[A] = i[A]);
          else r.punycode = i;
        })(ga);
      })(De, De.exports)),
    De.exports
  );
}
var Aa = ba();
const Sa = He(Aa);
var ur, tn;
function Pe() {
  return (tn || ((tn = 1), (ur = TypeError)), ur);
}
var cr, nn;
function Ke() {
  if (nn) return cr;
  nn = 1;
  var e = typeof Map == "function" && Map.prototype,
    t =
      Object.getOwnPropertyDescriptor && e
        ? Object.getOwnPropertyDescriptor(Map.prototype, "size")
        : null,
    r = e && t && typeof t.get == "function" ? t.get : null,
    a = e && Map.prototype.forEach,
    v = typeof Set == "function" && Set.prototype,
    o =
      Object.getOwnPropertyDescriptor && v
        ? Object.getOwnPropertyDescriptor(Set.prototype, "size")
        : null,
    i = v && o && typeof o.get == "function" ? o.get : null,
    n = v && Set.prototype.forEach,
    m = typeof WeakMap == "function" && WeakMap.prototype,
    c = m ? WeakMap.prototype.has : null,
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
    $ = Array.prototype.join,
    q = Array.prototype.slice,
    C = Math.floor,
    j = typeof BigInt == "function" ? BigInt.prototype.valueOf : null,
    x = Object.getOwnPropertySymbols,
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
  var ee = go,
    T = ee.custom,
    F = M(T) ? T : null,
    B = { __proto__: null, double: '"', single: "'" },
    L = { __proto__: null, double: /(["\\])/g, single: /(['\\])/g };
  cr = function f(y, J, X, re) {
    var W = J || {};
    if (oe(W, "quoteStyle") && !oe(B, W.quoteStyle))
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
    if (typeof y == "string") return jt(y, W);
    if (typeof y == "number") {
      if (y === 0) return 1 / 0 / y > 0 ? "0" : "-0";
      var de = String(y);
      return Oe ? k(y, de) : de;
    }
    if (typeof y == "bigint") {
      var Ee = String(y) + "n";
      return Oe ? k(y, Ee) : Ee;
    }
    var er = typeof W.depth > "u" ? 5 : W.depth;
    if ((typeof X > "u" && (X = 0), X >= er && er > 0 && typeof y == "object"))
      return Z(y) ? "[Array]" : "[Object]";
    var Ie = Mo(W, X);
    if (typeof re > "u") re = [];
    else if (fe(re, y) >= 0) return "[Circular]";
    function ve(_e, je, jo) {
      if ((je && ((re = q.call(re)), re.push(je)), jo)) {
        var Qt = { depth: W.depth };
        return (
          oe(W, "quoteStyle") && (Qt.quoteStyle = W.quoteStyle),
          f(_e, Qt, X + 1, re)
        );
      }
      return f(_e, W, X + 1, re);
    }
    if (typeof y == "function" && !D(y)) {
      var Lt = ue(y),
        Wt = Me(y, ve);
      return (
        "[Function" +
        (Lt ? ": " + Lt : " (anonymous)") +
        "]" +
        (Wt.length > 0 ? " { " + $.call(Wt, ", ") + " }" : "")
      );
    }
    if (M(y)) {
      var zt = G
        ? w.call(String(y), /^(Symbol\(.*\))_[^)]*$/, "$1")
        : Y.call(y);
      return typeof y == "object" && !G ? Fe(zt) : zt;
    }
    if (Do(y)) {
      for (
        var ke = "<" + R.call(String(y.nodeName)),
          rr = y.attributes || [],
          Be = 0;
        Be < rr.length;
        Be++
      )
        ke += " " + rr[Be].name + "=" + z(Q(rr[Be].value), "double", W);
      return (
        (ke += ">"),
        y.childNodes && y.childNodes.length && (ke += "..."),
        (ke += "</" + R.call(String(y.nodeName)) + ">"),
        ke
      );
    }
    if (Z(y)) {
      if (y.length === 0) return "[]";
      var tr = Me(y, ve);
      return Ie && !qo(tr)
        ? "[" + Xe(tr, Ie) + "]"
        : "[ " + $.call(tr, ", ") + " ]";
    }
    if (P(y)) {
      var nr = Me(y, ve);
      return !("cause" in Error.prototype) &&
        "cause" in y &&
        !ae.call(y, "cause")
        ? "{ [" +
            String(y) +
            "] " +
            $.call(A.call("[cause]: " + ve(y.cause), nr), ", ") +
            " }"
        : nr.length === 0
          ? "[" + String(y) + "]"
          : "{ [" + String(y) + "] " + $.call(nr, ", ") + " }";
    }
    if (typeof y == "object" && Se) {
      if (F && typeof y[F] == "function" && ee) return ee(y, { depth: er - X });
      if (Se !== "symbol" && typeof y.inspect == "function") return y.inspect();
    }
    if (V(y)) {
      var Ht = [];
      return (
        a &&
          a.call(y, function (_e, je) {
            Ht.push(ve(je, y, !0) + " => " + ve(_e, y));
          }),
        Gt("Map", r.call(y), Ht, Ie)
      );
    }
    if (ye(y)) {
      var Kt = [];
      return (
        n &&
          n.call(y, function (_e) {
            Kt.push(ve(_e, y));
          }),
        Gt("Set", i.call(y), Kt, Ie)
      );
    }
    if (ce(y)) return Ze("WeakMap");
    if (ko(y)) return Ze("WeakSet");
    if (pe(y)) return Ze("WeakRef");
    if (I(y)) return Fe(ve(Number(y)));
    if (K(y)) return Fe(ve(j.call(y)));
    if (N(y)) return Fe(b.call(y));
    if (_(y)) return Fe(ve(String(y)));
    if (typeof window < "u" && y === window) return "{ [object Window] }";
    if (
      (typeof globalThis < "u" && y === globalThis) ||
      (typeof We < "u" && y === We)
    )
      return "{ [object globalThis] }";
    if (!ne(y) && !D(y)) {
      var or = Me(y, ve),
        Vt = se
          ? se(y) === Object.prototype
          : y instanceof Object || y.constructor === Object,
        ar = y instanceof Object ? "" : "null prototype",
        Jt =
          !Vt && te && Object(y) === y && te in y
            ? s.call(le(y), 8, -1)
            : ar
              ? "Object"
              : "",
        Bo =
          Vt || typeof y.constructor != "function"
            ? ""
            : y.constructor.name
              ? y.constructor.name + " "
              : "",
        ir =
          Bo +
          (Jt || ar
            ? "[" + $.call(A.call([], Jt || [], ar || []), ": ") + "] "
            : "");
      return or.length === 0
        ? ir + "{}"
        : Ie
          ? ir + "{" + Xe(or, Ie) + "}"
          : ir + "{ " + $.call(or, ", ") + " }";
    }
    return String(y);
  };
  function z(f, y, J) {
    var X = J.quoteStyle || y,
      re = B[X];
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
  function _(f) {
    return le(f) === "[object String]" && H(f);
  }
  function I(f) {
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
    if (!f || typeof f != "object" || !j) return !1;
    try {
      return (j.call(f), !0);
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
  function ko(f) {
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
  function Do(f) {
    return !f || typeof f != "object"
      ? !1
      : typeof HTMLElement < "u" && f instanceof HTMLElement
        ? !0
        : typeof f.nodeName == "string" && typeof f.getAttribute == "function";
  }
  function jt(f, y) {
    if (f.length > y.maxStringLength) {
      var J = f.length - y.maxStringLength,
        X = "... " + J + " more character" + (J > 1 ? "s" : "");
      return jt(s.call(f, 0, y.maxStringLength), y) + X;
    }
    var re = L[y.quoteStyle || "single"];
    re.lastIndex = 0;
    var W = w.call(w.call(f, re, "\\$1"), /[\x00-\x1f]/g, Uo);
    return z(W, "single", y);
  }
  function Uo(f) {
    var y = f.charCodeAt(0),
      J = { 8: "b", 9: "t", 10: "n", 12: "f", 13: "r" }[y];
    return J ? "\\" + J : "\\x" + (y < 16 ? "0" : "") + S.call(y.toString(16));
  }
  function Fe(f) {
    return "Object(" + f + ")";
  }
  function Ze(f) {
    return f + " { ? }";
  }
  function Gt(f, y, J, X) {
    var re = X ? Xe(J, X) : $.call(J, ", ");
    return f + " (" + y + ") {" + re + "}";
  }
  function qo(f) {
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
  function Mo(f, y) {
    var J;
    if (f.indent === "	") J = "	";
    else if (typeof f.indent == "number" && f.indent > 0)
      J = $.call(Array(f.indent + 1), " ");
    else return null;
    return { base: J, prev: $.call(Array(y + 1), J) };
  }
  function Xe(f, y) {
    if (f.length === 0) return "";
    var J =
      `
` +
      y.prev +
      y.base;
    return (
      J +
      $.call(f, "," + J) +
      `
` +
      y.prev
    );
  }
  function Me(f, y) {
    var J = Z(f),
      X = [];
    if (J) {
      X.length = f.length;
      for (var re = 0; re < f.length; re++)
        X[re] = oe(f, re) ? y(f[re], f) : "";
    }
    var W = typeof x == "function" ? x(f) : [],
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
    if (typeof x == "function")
      for (var Ee = 0; Ee < W.length; Ee++)
        ae.call(f, W[Ee]) && X.push("[" + y(W[Ee]) + "]: " + y(f[W[Ee]], f));
    return X;
  }
  return cr;
}
var pr, on;
function Ea() {
  if (on) return pr;
  on = 1;
  var e = Ke(),
    t = Pe(),
    r = function (n, m, c) {
      for (var u = n, h; (h = u.next) != null; u = h)
        if (h.key === m)
          return ((u.next = h.next), c || ((h.next = n.next), (n.next = h)), h);
    },
    a = function (n, m) {
      if (n) {
        var c = r(n, m);
        return c && c.value;
      }
    },
    v = function (n, m, c) {
      var u = r(n, m);
      u ? (u.value = c) : (n.next = { key: m, next: n.next, value: c });
    },
    o = function (n, m) {
      return n ? !!r(n, m) : !1;
    },
    i = function (n, m) {
      if (n) return r(n, m, !0);
    };
  return (
    (pr = function () {
      var m,
        c = {
          assert: function (u) {
            if (!c.has(u)) throw new t("Side channel does not contain " + e(u));
          },
          delete: function (u) {
            var h = m && m.next,
              g = i(m, u);
            return (g && h && h === g && (m = void 0), !!g);
          },
          get: function (u) {
            return a(m, u);
          },
          has: function (u) {
            return o(m, u);
          },
          set: function (u, h) {
            (m || (m = { next: void 0 }), v(m, u, h));
          },
        };
      return c;
    }),
    pr
  );
}
var yr, an;
function wa() {
  return (an || ((an = 1), (yr = Object)), yr);
}
var dr, sn;
function wt() {
  return (sn || ((sn = 1), (dr = Error)), dr);
}
var hr, ln;
function Pt() {
  return (ln || ((ln = 1), (hr = EvalError)), hr);
}
var vr, fn;
function Ot() {
  return (fn || ((fn = 1), (vr = RangeError)), vr);
}
var mr, un;
function Rt() {
  return (un || ((un = 1), (mr = ReferenceError)), mr);
}
var gr, cn;
function It() {
  return (cn || ((cn = 1), (gr = SyntaxError)), gr);
}
var br, pn;
function _t() {
  return (pn || ((pn = 1), (br = URIError)), br);
}
var Ar, yn;
function Tt() {
  return (yn || ((yn = 1), (Ar = Math.abs)), Ar);
}
var Sr, dn;
function xt() {
  return (dn || ((dn = 1), (Sr = Math.floor)), Sr);
}
var Er, hn;
function $t() {
  return (hn || ((hn = 1), (Er = Math.max)), Er);
}
var wr, vn;
function Nt() {
  return (vn || ((vn = 1), (wr = Math.min)), wr);
}
var Pr, mn;
function Ct() {
  return (mn || ((mn = 1), (Pr = Math.pow)), Pr);
}
var Or, gn;
function Ft() {
  return (gn || ((gn = 1), (Or = Math.round)), Or);
}
var Rr, bn;
function Pa() {
  return (
    bn ||
      ((bn = 1),
      (Rr =
        Number.isNaN ||
        function (t) {
          return t !== t;
        })),
    Rr
  );
}
var Ir, An;
function kt() {
  if (An) return Ir;
  An = 1;
  var e = Pa();
  return (
    (Ir = function (r) {
      return e(r) || r === 0 ? r : r < 0 ? -1 : 1;
    }),
    Ir
  );
}
var _r, Sn;
function Oa() {
  return (Sn || ((Sn = 1), (_r = Object.getOwnPropertyDescriptor)), _r);
}
var Tr, En;
function Ra() {
  if (En) return Tr;
  En = 1;
  var e = Oa();
  if (e)
    try {
      e([], "length");
    } catch {
      e = null;
    }
  return ((Tr = e), Tr);
}
var xr, wn;
function Dt() {
  if (wn) return xr;
  wn = 1;
  var e = Object.defineProperty || !1;
  if (e)
    try {
      e({}, "a", { value: 1 });
    } catch {
      e = !1;
    }
  return ((xr = e), xr);
}
var $r, Pn;
function Ia() {
  return (
    Pn ||
      ((Pn = 1),
      ($r = function () {
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
        var v = 42;
        t[r] = v;
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
          if (n.value !== v || n.enumerable !== !0) return !1;
        }
        return !0;
      })),
    $r
  );
}
var Nr, On;
function _a() {
  if (On) return Nr;
  On = 1;
  var e = typeof Symbol < "u" && Symbol,
    t = Ia();
  return (
    (Nr = function () {
      return typeof e != "function" ||
        typeof Symbol != "function" ||
        typeof e("foo") != "symbol" ||
        typeof Symbol("bar") != "symbol"
        ? !1
        : t();
    }),
    Nr
  );
}
var Cr, Rn;
function Ve() {
  return (
    Rn ||
      ((Rn = 1),
      (Cr = (typeof Reflect < "u" && Reflect.getPrototypeOf) || null)),
    Cr
  );
}
var Fr, In;
function Ta() {
  return (In || ((In = 1), (Fr = Object)), Fr);
}
var kr, _n;
function Je() {
  if (_n) return kr;
  _n = 1;
  var e = Ta();
  return ((kr = e.getPrototypeOf || null), kr);
}
var Dr, Tn;
function xa() {
  if (Tn) return Dr;
  Tn = 1;
  var e = "Function.prototype.bind called on incompatible ",
    t = Object.prototype.toString,
    r = Math.max,
    a = "[object Function]",
    v = function (m, c) {
      for (var u = [], h = 0; h < m.length; h += 1) u[h] = m[h];
      for (var g = 0; g < c.length; g += 1) u[g + m.length] = c[g];
      return u;
    },
    o = function (m, c) {
      for (var u = [], h = c, g = 0; h < m.length; h += 1, g += 1) u[g] = m[h];
      return u;
    },
    i = function (n, m) {
      for (var c = "", u = 0; u < n.length; u += 1)
        ((c += n[u]), u + 1 < n.length && (c += m));
      return c;
    };
  return (
    (Dr = function (m) {
      var c = this;
      if (typeof c != "function" || t.apply(c) !== a)
        throw new TypeError(e + c);
      for (
        var u = o(arguments, 1),
          h,
          g = function () {
            if (this instanceof h) {
              var d = c.apply(this, v(u, arguments));
              return Object(d) === d ? d : this;
            }
            return c.apply(m, v(u, arguments));
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
    Dr
  );
}
var Ur, xn;
function Ne() {
  if (xn) return Ur;
  xn = 1;
  var e = xa();
  return ((Ur = Function.prototype.bind || e), Ur);
}
var qr, $n;
function Ue() {
  return ($n || (($n = 1), (qr = Function.prototype.call)), qr);
}
var Mr, Nn;
function Qe() {
  return (Nn || ((Nn = 1), (Mr = Function.prototype.apply)), Mr);
}
var Br, Cn;
function $a() {
  return (
    Cn || ((Cn = 1), (Br = typeof Reflect < "u" && Reflect && Reflect.apply)),
    Br
  );
}
var jr, Fn;
function Na() {
  if (Fn) return jr;
  Fn = 1;
  var e = Ne(),
    t = Qe(),
    r = Ue(),
    a = $a();
  return ((jr = a || e.call(r, t)), jr);
}
var Gr, kn;
function Ao() {
  if (kn) return Gr;
  kn = 1;
  var e = Ne(),
    t = Pe(),
    r = Ue(),
    a = Na();
  return (
    (Gr = function (o) {
      if (o.length < 1 || typeof o[0] != "function")
        throw new t("a function is required");
      return a(e, r, o);
    }),
    Gr
  );
}
var Lr, Dn;
function Ca() {
  return (Dn || ((Dn = 1), (Lr = Object.getOwnPropertyDescriptor)), Lr);
}
var Wr, Un;
function Fa() {
  if (Un) return Wr;
  Un = 1;
  var e = Ca();
  if (e)
    try {
      e([], "length");
    } catch {
      e = null;
    }
  return ((Wr = e), Wr);
}
var zr, qn;
function ka() {
  if (qn) return zr;
  qn = 1;
  var e = Ao(),
    t = Fa(),
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
    v = Object,
    o = v.getPrototypeOf;
  return (
    (zr =
      a && typeof a.get == "function"
        ? e([a.get])
        : typeof o == "function"
          ? function (n) {
              return o(n == null ? n : v(n));
            }
          : !1),
    zr
  );
}
var Hr, Mn;
function Ut() {
  if (Mn) return Hr;
  Mn = 1;
  var e = Ve(),
    t = Je(),
    r = ka();
  return (
    (Hr = e
      ? function (v) {
          return e(v);
        }
      : t
        ? function (v) {
            if (!v || (typeof v != "object" && typeof v != "function"))
              throw new TypeError("getProto: not an object");
            return t(v);
          }
        : r
          ? function (v) {
              return r(v);
            }
          : null),
    Hr
  );
}
var Kr, Bn;
function qt() {
  if (Bn) return Kr;
  Bn = 1;
  var e = Function.prototype.call,
    t = Object.prototype.hasOwnProperty,
    r = Ne();
  return ((Kr = r.call(e, t)), Kr);
}
var Vr, jn;
function Da() {
  if (jn) return Vr;
  jn = 1;
  var e,
    t = wa(),
    r = wt(),
    a = Pt(),
    v = Ot(),
    o = Rt(),
    i = It(),
    n = Pe(),
    m = _t(),
    c = Tt(),
    u = xt(),
    h = $t(),
    g = Nt(),
    p = Ct(),
    b = Ft(),
    E = kt(),
    l = Function,
    d = function (D) {
      try {
        return l('"use strict"; return (' + D + ").constructor;")();
      } catch {}
    },
    s = Ra(),
    w = Dt(),
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
    O = _a()(),
    A = Ut(),
    $ = Je(),
    q = Ve(),
    C = Qe(),
    j = Ue(),
    x = {},
    Y = typeof Uint8Array > "u" || !A ? e : A(Uint8Array),
    G = {
      __proto__: null,
      "%AggregateError%": typeof AggregateError > "u" ? e : AggregateError,
      "%Array%": Array,
      "%ArrayBuffer%": typeof ArrayBuffer > "u" ? e : ArrayBuffer,
      "%ArrayIteratorPrototype%": O && A ? A([][Symbol.iterator]()) : e,
      "%AsyncFromSyncIteratorPrototype%": e,
      "%AsyncFunction%": x,
      "%AsyncGenerator%": x,
      "%AsyncGeneratorFunction%": x,
      "%AsyncIteratorPrototype%": x,
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
      "%GeneratorFunction%": x,
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
      "%RangeError%": v,
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
      "%URIError%": m,
      "%WeakMap%": typeof WeakMap > "u" ? e : WeakMap,
      "%WeakRef%": typeof WeakRef > "u" ? e : WeakRef,
      "%WeakSet%": typeof WeakSet > "u" ? e : WeakSet,
      "%Function.prototype.call%": j,
      "%Function.prototype.apply%": C,
      "%Object.defineProperty%": w,
      "%Object.getPrototypeOf%": $,
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
      var _;
      if (P === "%AsyncFunction%") _ = d("async function () {}");
      else if (P === "%GeneratorFunction%") _ = d("function* () {}");
      else if (P === "%AsyncGeneratorFunction%") _ = d("async function* () {}");
      else if (P === "%AsyncGenerator%") {
        var I = D("%AsyncGeneratorFunction%");
        I && (_ = I.prototype);
      } else if (P === "%AsyncIteratorPrototype%") {
        var N = D("%AsyncGenerator%");
        N && A && (_ = A(N.prototype));
      }
      return ((G[P] = _), _);
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
    k = Ne(),
    ee = qt(),
    T = k.call(j, Array.prototype.concat),
    F = k.call(C, Array.prototype.splice),
    B = k.call(j, String.prototype.replace),
    L = k.call(j, String.prototype.slice),
    z = k.call(j, RegExp.prototype.exec),
    Q =
      /[^%.[\]]+|\[(?:(-?\d+(?:\.\d+)?)|(["'])((?:(?!\2)[^\\]|\\.)*?)\2)\]|(?=(?:\.|\[\])(?:\.|\[\]|%$))/g,
    H = /\\(\\)?/g,
    Z = function (P) {
      var _ = L(P, 0, 1),
        I = L(P, -1);
      if (_ === "%" && I !== "%")
        throw new i("invalid intrinsic syntax, expected closing `%`");
      if (I === "%" && _ !== "%")
        throw new i("invalid intrinsic syntax, expected opening `%`");
      var N = [];
      return (
        B(P, Q, function (M, K, U, oe) {
          N[N.length] = U ? B(oe, H, "$1") : K || M;
        }),
        N
      );
    },
    ne = function (P, _) {
      var I = P,
        N;
      if ((ee(se, I) && ((N = se[I]), (I = "%" + N[0] + "%")), ee(G, I))) {
        var M = G[I];
        if ((M === x && (M = ae(I)), typeof M > "u" && !_))
          throw new n(
            "intrinsic " +
              P +
              " exists, but is not available. Please file an issue!",
          );
        return { alias: N, name: I, value: M };
      }
      throw new i("intrinsic " + P + " does not exist!");
    };
  return (
    (Vr = function (P, _) {
      if (typeof P != "string" || P.length === 0)
        throw new n("intrinsic name must be a non-empty string");
      if (arguments.length > 1 && typeof _ != "boolean")
        throw new n('"allowMissing" argument must be a boolean');
      if (z(/^%?[^%]*%?$/, P) === null)
        throw new i(
          "`%` may not be present anywhere but at the beginning and end of the intrinsic name",
        );
      var I = Z(P),
        N = I.length > 0 ? I[0] : "",
        M = ne("%" + N + "%", _),
        K = M.name,
        U = M.value,
        oe = !1,
        le = M.alias;
      le && ((N = le[0]), F(I, T([0, 1], le)));
      for (var ue = 1, fe = !0; ue < I.length; ue += 1) {
        var V = I[ue],
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
            if (!_)
              throw new n(
                "base intrinsic for " +
                  P +
                  " exists, but the property is not available.",
              );
            return;
          }
          if (s && ue + 1 >= I.length) {
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
    Vr
  );
}
var Jr, Gn;
function Ua() {
  return (Gn || ((Gn = 1), (Jr = Object)), Jr);
}
var Qr, Ln;
function qa() {
  return (Ln || ((Ln = 1), (Qr = Object.getOwnPropertyDescriptor)), Qr);
}
var Yr, Wn;
function Ma() {
  if (Wn) return Yr;
  Wn = 1;
  var e = qa();
  if (e)
    try {
      e([], "length");
    } catch {
      e = null;
    }
  return ((Yr = e), Yr);
}
var Zr, zn;
function Ba() {
  return (
    zn ||
      ((zn = 1),
      (Zr = function () {
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
        var v = 42;
        t[r] = v;
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
          if (n.value !== v || n.enumerable !== !0) return !1;
        }
        return !0;
      })),
    Zr
  );
}
var Xr, Hn;
function ja() {
  if (Hn) return Xr;
  Hn = 1;
  var e = typeof Symbol < "u" && Symbol,
    t = Ba();
  return (
    (Xr = function () {
      return typeof e != "function" ||
        typeof Symbol != "function" ||
        typeof e("foo") != "symbol" ||
        typeof Symbol("bar") != "symbol"
        ? !1
        : t();
    }),
    Xr
  );
}
var et, Kn;
function Ga() {
  if (Kn) return et;
  Kn = 1;
  var e,
    t = Ua(),
    r = wt(),
    a = Pt(),
    v = Ot(),
    o = Rt(),
    i = It(),
    n = Pe(),
    m = _t(),
    c = Tt(),
    u = xt(),
    h = $t(),
    g = Nt(),
    p = Ct(),
    b = Ft(),
    E = kt(),
    l = Function,
    d = function (D) {
      try {
        return l('"use strict"; return (' + D + ").constructor;")();
      } catch {}
    },
    s = Ma(),
    w = Dt(),
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
    A = Ut(),
    $ = Je(),
    q = Ve(),
    C = Qe(),
    j = Ue(),
    x = {},
    Y = typeof Uint8Array > "u" || !A ? e : A(Uint8Array),
    G = {
      __proto__: null,
      "%AggregateError%": typeof AggregateError > "u" ? e : AggregateError,
      "%Array%": Array,
      "%ArrayBuffer%": typeof ArrayBuffer > "u" ? e : ArrayBuffer,
      "%ArrayIteratorPrototype%": O && A ? A([][Symbol.iterator]()) : e,
      "%AsyncFromSyncIteratorPrototype%": e,
      "%AsyncFunction%": x,
      "%AsyncGenerator%": x,
      "%AsyncGeneratorFunction%": x,
      "%AsyncIteratorPrototype%": x,
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
      "%GeneratorFunction%": x,
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
      "%RangeError%": v,
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
      "%URIError%": m,
      "%WeakMap%": typeof WeakMap > "u" ? e : WeakMap,
      "%WeakRef%": typeof WeakRef > "u" ? e : WeakRef,
      "%WeakSet%": typeof WeakSet > "u" ? e : WeakSet,
      "%Function.prototype.call%": j,
      "%Function.prototype.apply%": C,
      "%Object.defineProperty%": w,
      "%Object.getPrototypeOf%": $,
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
      var _;
      if (P === "%AsyncFunction%") _ = d("async function () {}");
      else if (P === "%GeneratorFunction%") _ = d("function* () {}");
      else if (P === "%AsyncGeneratorFunction%") _ = d("async function* () {}");
      else if (P === "%AsyncGenerator%") {
        var I = D("%AsyncGeneratorFunction%");
        I && (_ = I.prototype);
      } else if (P === "%AsyncIteratorPrototype%") {
        var N = D("%AsyncGenerator%");
        N && A && (_ = A(N.prototype));
      }
      return ((G[P] = _), _);
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
    k = Ne(),
    ee = qt(),
    T = k.call(j, Array.prototype.concat),
    F = k.call(C, Array.prototype.splice),
    B = k.call(j, String.prototype.replace),
    L = k.call(j, String.prototype.slice),
    z = k.call(j, RegExp.prototype.exec),
    Q =
      /[^%.[\]]+|\[(?:(-?\d+(?:\.\d+)?)|(["'])((?:(?!\2)[^\\]|\\.)*?)\2)\]|(?=(?:\.|\[\])(?:\.|\[\]|%$))/g,
    H = /\\(\\)?/g,
    Z = function (P) {
      var _ = L(P, 0, 1),
        I = L(P, -1);
      if (_ === "%" && I !== "%")
        throw new i("invalid intrinsic syntax, expected closing `%`");
      if (I === "%" && _ !== "%")
        throw new i("invalid intrinsic syntax, expected opening `%`");
      var N = [];
      return (
        B(P, Q, function (M, K, U, oe) {
          N[N.length] = U ? B(oe, H, "$1") : K || M;
        }),
        N
      );
    },
    ne = function (P, _) {
      var I = P,
        N;
      if ((ee(se, I) && ((N = se[I]), (I = "%" + N[0] + "%")), ee(G, I))) {
        var M = G[I];
        if ((M === x && (M = ae(I)), typeof M > "u" && !_))
          throw new n(
            "intrinsic " +
              P +
              " exists, but is not available. Please file an issue!",
          );
        return { alias: N, name: I, value: M };
      }
      throw new i("intrinsic " + P + " does not exist!");
    };
  return (
    (et = function (P, _) {
      if (typeof P != "string" || P.length === 0)
        throw new n("intrinsic name must be a non-empty string");
      if (arguments.length > 1 && typeof _ != "boolean")
        throw new n('"allowMissing" argument must be a boolean');
      if (z(/^%?[^%]*%?$/, P) === null)
        throw new i(
          "`%` may not be present anywhere but at the beginning and end of the intrinsic name",
        );
      var I = Z(P),
        N = I.length > 0 ? I[0] : "",
        M = ne("%" + N + "%", _),
        K = M.name,
        U = M.value,
        oe = !1,
        le = M.alias;
      le && ((N = le[0]), F(I, T([0, 1], le)));
      for (var ue = 1, fe = !0; ue < I.length; ue += 1) {
        var V = I[ue],
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
            if (!_)
              throw new n(
                "base intrinsic for " +
                  P +
                  " exists, but the property is not available.",
              );
            return;
          }
          if (s && ue + 1 >= I.length) {
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
    et
  );
}
var rt, Vn;
function So() {
  if (Vn) return rt;
  Vn = 1;
  var e = Ga(),
    t = Ao(),
    r = t([e("%String.prototype.indexOf%")]);
  return (
    (rt = function (v, o) {
      var i = e(v, !!o);
      return typeof i == "function" && r(v, ".prototype.") > -1 ? t([i]) : i;
    }),
    rt
  );
}
var tt, Jn;
function Eo() {
  if (Jn) return tt;
  Jn = 1;
  var e = Da(),
    t = So(),
    r = Ke(),
    a = Pe(),
    v = e("%Map%", !0),
    o = t("Map.prototype.get", !0),
    i = t("Map.prototype.set", !0),
    n = t("Map.prototype.has", !0),
    m = t("Map.prototype.delete", !0),
    c = t("Map.prototype.size", !0);
  return (
    (tt =
      !!v &&
      function () {
        var h,
          g = {
            assert: function (p) {
              if (!g.has(p))
                throw new a("Side channel does not contain " + r(p));
            },
            delete: function (p) {
              if (h) {
                var b = m(h, p);
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
              (h || (h = new v()), i(h, p, b));
            },
          };
        return g;
      }),
    tt
  );
}
var nt, Qn;
function La() {
  return (Qn || ((Qn = 1), (nt = Object)), nt);
}
var ot, Yn;
function Wa() {
  return (Yn || ((Yn = 1), (ot = Object.getOwnPropertyDescriptor)), ot);
}
var at, Zn;
function za() {
  if (Zn) return at;
  Zn = 1;
  var e = Wa();
  if (e)
    try {
      e([], "length");
    } catch {
      e = null;
    }
  return ((at = e), at);
}
var it, Xn;
function Ha() {
  return (
    Xn ||
      ((Xn = 1),
      (it = function () {
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
        var v = 42;
        t[r] = v;
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
          if (n.value !== v || n.enumerable !== !0) return !1;
        }
        return !0;
      })),
    it
  );
}
var st, eo;
function Ka() {
  if (eo) return st;
  eo = 1;
  var e = typeof Symbol < "u" && Symbol,
    t = Ha();
  return (
    (st = function () {
      return typeof e != "function" ||
        typeof Symbol != "function" ||
        typeof e("foo") != "symbol" ||
        typeof Symbol("bar") != "symbol"
        ? !1
        : t();
    }),
    st
  );
}
var lt, ro;
function Va() {
  if (ro) return lt;
  ro = 1;
  var e,
    t = La(),
    r = wt(),
    a = Pt(),
    v = Ot(),
    o = Rt(),
    i = It(),
    n = Pe(),
    m = _t(),
    c = Tt(),
    u = xt(),
    h = $t(),
    g = Nt(),
    p = Ct(),
    b = Ft(),
    E = kt(),
    l = Function,
    d = function (D) {
      try {
        return l('"use strict"; return (' + D + ").constructor;")();
      } catch {}
    },
    s = za(),
    w = Dt(),
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
    O = Ka()(),
    A = Ut(),
    $ = Je(),
    q = Ve(),
    C = Qe(),
    j = Ue(),
    x = {},
    Y = typeof Uint8Array > "u" || !A ? e : A(Uint8Array),
    G = {
      __proto__: null,
      "%AggregateError%": typeof AggregateError > "u" ? e : AggregateError,
      "%Array%": Array,
      "%ArrayBuffer%": typeof ArrayBuffer > "u" ? e : ArrayBuffer,
      "%ArrayIteratorPrototype%": O && A ? A([][Symbol.iterator]()) : e,
      "%AsyncFromSyncIteratorPrototype%": e,
      "%AsyncFunction%": x,
      "%AsyncGenerator%": x,
      "%AsyncGeneratorFunction%": x,
      "%AsyncIteratorPrototype%": x,
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
      "%GeneratorFunction%": x,
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
      "%RangeError%": v,
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
      "%URIError%": m,
      "%WeakMap%": typeof WeakMap > "u" ? e : WeakMap,
      "%WeakRef%": typeof WeakRef > "u" ? e : WeakRef,
      "%WeakSet%": typeof WeakSet > "u" ? e : WeakSet,
      "%Function.prototype.call%": j,
      "%Function.prototype.apply%": C,
      "%Object.defineProperty%": w,
      "%Object.getPrototypeOf%": $,
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
      var _;
      if (P === "%AsyncFunction%") _ = d("async function () {}");
      else if (P === "%GeneratorFunction%") _ = d("function* () {}");
      else if (P === "%AsyncGeneratorFunction%") _ = d("async function* () {}");
      else if (P === "%AsyncGenerator%") {
        var I = D("%AsyncGeneratorFunction%");
        I && (_ = I.prototype);
      } else if (P === "%AsyncIteratorPrototype%") {
        var N = D("%AsyncGenerator%");
        N && A && (_ = A(N.prototype));
      }
      return ((G[P] = _), _);
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
    k = Ne(),
    ee = qt(),
    T = k.call(j, Array.prototype.concat),
    F = k.call(C, Array.prototype.splice),
    B = k.call(j, String.prototype.replace),
    L = k.call(j, String.prototype.slice),
    z = k.call(j, RegExp.prototype.exec),
    Q =
      /[^%.[\]]+|\[(?:(-?\d+(?:\.\d+)?)|(["'])((?:(?!\2)[^\\]|\\.)*?)\2)\]|(?=(?:\.|\[\])(?:\.|\[\]|%$))/g,
    H = /\\(\\)?/g,
    Z = function (P) {
      var _ = L(P, 0, 1),
        I = L(P, -1);
      if (_ === "%" && I !== "%")
        throw new i("invalid intrinsic syntax, expected closing `%`");
      if (I === "%" && _ !== "%")
        throw new i("invalid intrinsic syntax, expected opening `%`");
      var N = [];
      return (
        B(P, Q, function (M, K, U, oe) {
          N[N.length] = U ? B(oe, H, "$1") : K || M;
        }),
        N
      );
    },
    ne = function (P, _) {
      var I = P,
        N;
      if ((ee(se, I) && ((N = se[I]), (I = "%" + N[0] + "%")), ee(G, I))) {
        var M = G[I];
        if ((M === x && (M = ae(I)), typeof M > "u" && !_))
          throw new n(
            "intrinsic " +
              P +
              " exists, but is not available. Please file an issue!",
          );
        return { alias: N, name: I, value: M };
      }
      throw new i("intrinsic " + P + " does not exist!");
    };
  return (
    (lt = function (P, _) {
      if (typeof P != "string" || P.length === 0)
        throw new n("intrinsic name must be a non-empty string");
      if (arguments.length > 1 && typeof _ != "boolean")
        throw new n('"allowMissing" argument must be a boolean');
      if (z(/^%?[^%]*%?$/, P) === null)
        throw new i(
          "`%` may not be present anywhere but at the beginning and end of the intrinsic name",
        );
      var I = Z(P),
        N = I.length > 0 ? I[0] : "",
        M = ne("%" + N + "%", _),
        K = M.name,
        U = M.value,
        oe = !1,
        le = M.alias;
      le && ((N = le[0]), F(I, T([0, 1], le)));
      for (var ue = 1, fe = !0; ue < I.length; ue += 1) {
        var V = I[ue],
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
            if (!_)
              throw new n(
                "base intrinsic for " +
                  P +
                  " exists, but the property is not available.",
              );
            return;
          }
          if (s && ue + 1 >= I.length) {
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
    lt
  );
}
var ft, to;
function Ja() {
  if (to) return ft;
  to = 1;
  var e = Va(),
    t = So(),
    r = Ke(),
    a = Eo(),
    v = Pe(),
    o = e("%WeakMap%", !0),
    i = t("WeakMap.prototype.get", !0),
    n = t("WeakMap.prototype.set", !0),
    m = t("WeakMap.prototype.has", !0),
    c = t("WeakMap.prototype.delete", !0);
  return (
    (ft = o
      ? function () {
          var h,
            g,
            p = {
              assert: function (b) {
                if (!p.has(b))
                  throw new v("Side channel does not contain " + r(b));
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
                  ? m(h, b)
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
    ft
  );
}
var ut, no;
function Qa() {
  if (no) return ut;
  no = 1;
  var e = Pe(),
    t = Ke(),
    r = Ea(),
    a = Eo(),
    v = Ja(),
    o = v || a || r;
  return (
    (ut = function () {
      var n,
        m = {
          assert: function (c) {
            if (!m.has(c)) throw new e("Side channel does not contain " + t(c));
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
      return m;
    }),
    ut
  );
}
var ct, oo;
function Mt() {
  if (oo) return ct;
  oo = 1;
  var e = String.prototype.replace,
    t = /%20/g,
    r = { RFC1738: "RFC1738", RFC3986: "RFC3986" };
  return (
    (ct = {
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
    ct
  );
}
var pt, ao;
function wo() {
  if (ao) return pt;
  ao = 1;
  var e = Mt(),
    t = Object.prototype.hasOwnProperty,
    r = Array.isArray,
    a = (function () {
      for (var l = [], d = 0; d < 256; ++d)
        l.push("%" + ((d < 16 ? "0" : "") + d.toString(16)).toUpperCase());
      return l;
    })(),
    v = function (d) {
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
    m = function (l, d, s) {
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
      for (var A = "", $ = 0; $ < O.length; $ += c) {
        for (
          var q = O.length >= c ? O.slice($, $ + c) : O, C = [], j = 0;
          j < q.length;
          ++j
        ) {
          var x = q.charCodeAt(j);
          if (
            x === 45 ||
            x === 46 ||
            x === 95 ||
            x === 126 ||
            (x >= 48 && x <= 57) ||
            (x >= 65 && x <= 90) ||
            (x >= 97 && x <= 122) ||
            (R === e.RFC1738 && (x === 40 || x === 41))
          ) {
            C[C.length] = q.charAt(j);
            continue;
          }
          if (x < 128) {
            C[C.length] = a[x];
            continue;
          }
          if (x < 2048) {
            C[C.length] = a[192 | (x >> 6)] + a[128 | (x & 63)];
            continue;
          }
          if (x < 55296 || x >= 57344) {
            C[C.length] =
              a[224 | (x >> 12)] + a[128 | ((x >> 6) & 63)] + a[128 | (x & 63)];
            continue;
          }
          ((j += 1),
            (x = 65536 + (((x & 1023) << 10) | (q.charCodeAt(j) & 1023))),
            (C[C.length] =
              a[240 | (x >> 18)] +
              a[128 | ((x >> 12) & 63)] +
              a[128 | ((x >> 6) & 63)] +
              a[128 | (x & 63)]));
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
          var R = s[S], O = R.obj[R.prop], A = Object.keys(O), $ = 0;
          $ < A.length;
          ++$
        ) {
          var q = A[$],
            C = O[q];
          typeof C == "object" &&
            C !== null &&
            w.indexOf(C) === -1 &&
            (s.push({ obj: O, prop: q }), w.push(C));
        }
      return (v(s), d);
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
    (pt = {
      arrayToObject: o,
      assign: n,
      combine: b,
      compact: h,
      decode: m,
      encode: u,
      isBuffer: p,
      isRegExp: g,
      maybeMap: E,
      merge: i,
    }),
    pt
  );
}
var yt, io;
function Ya() {
  if (io) return yt;
  io = 1;
  var e = Qa(),
    t = wo(),
    r = Mt(),
    a = Object.prototype.hasOwnProperty,
    v = {
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
    m = Date.prototype.toISOString,
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
        return m.call(l);
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
    p = function E(l, d, s, w, S, R, O, A, $, q, C, j, x, Y, G, te, ae, se) {
      for (
        var k = l, ee = se, T = 0, F = !1;
        (ee = ee.get(g)) !== void 0 && !F;
      ) {
        var B = ee.get(l);
        if (((T += 1), typeof B < "u")) {
          if (B === T) throw new RangeError("Cyclic object value");
          F = !0;
        }
        typeof ee.get(g) > "u" && (T = 0);
      }
      if (
        (typeof q == "function"
          ? (k = q(d, k))
          : k instanceof Date
            ? (k = x(k))
            : s === "comma" &&
              o(k) &&
              (k = t.maybeMap(k, function (K) {
                return K instanceof Date ? x(K) : K;
              })),
        k === null)
      ) {
        if (R) return $ && !te ? $(d, u.encoder, ae, "key", Y) : d;
        k = "";
      }
      if (h(k) || t.isBuffer(k)) {
        if ($) {
          var L = te ? d : $(d, u.encoder, ae, "key", Y);
          return [G(L) + "=" + G($(k, u.encoder, ae, "value", Y))];
        }
        return [G(d) + "=" + G(String(k))];
      }
      var z = [];
      if (typeof k > "u") return z;
      var Q;
      if (s === "comma" && o(k))
        (te && $ && (k = t.maybeMap(k, $)),
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
          _ =
            typeof P == "object" && P && typeof P.value < "u" ? P.value : k[P];
        if (!(O && _ === null)) {
          var I = j && A ? String(P).replace(/\./g, "%2E") : String(P),
            N = o(k)
              ? typeof s == "function"
                ? s(ne, I)
                : ne
              : ne + (j ? "." + I : "[" + I + "]");
          se.set(l, T);
          var M = e();
          (M.set(g, se),
            n(
              z,
              E(
                _,
                N,
                s,
                w,
                S,
                R,
                O,
                A,
                s === "comma" && te && o(k) ? null : $,
                q,
                C,
                j,
                x,
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
        (l.arrayFormat in v
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
    (yt = function (E, l) {
      var d = E,
        s = b(l),
        w,
        S;
      typeof s.filter == "function"
        ? ((S = s.filter), (d = S("", d)))
        : o(s.filter) && ((S = s.filter), (w = S));
      var R = [];
      if (typeof d != "object" || d === null) return "";
      var O = v[s.arrayFormat],
        A = O === "comma" && s.commaRoundTrip;
      (w || (w = Object.keys(d)), s.sort && w.sort(s.sort));
      for (var $ = e(), q = 0; q < w.length; ++q) {
        var C = w[q],
          j = d[C];
        (s.skipNulls && j === null) ||
          n(
            R,
            p(
              j,
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
              $,
            ),
          );
      }
      var x = R.join(s.delimiter),
        Y = s.addQueryPrefix === !0 ? "?" : "";
      return (
        s.charsetSentinel &&
          (s.charset === "iso-8859-1"
            ? (Y += "utf8=%26%2310003%3B&")
            : (Y += "utf8=%E2%9C%93&")),
        x.length > 0 ? Y + x : ""
      );
    }),
    yt
  );
}
var dt, so;
function Za() {
  if (so) return dt;
  so = 1;
  var e = wo(),
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
    v = function (g) {
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
    m = function (p, b) {
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
            $ = A === -1 ? O.indexOf("=") : A + 1,
            q,
            C;
          ($ === -1
            ? ((q = b.decoder(O, a.decoder, R, "key")),
              (C = b.strictNullHandling ? null : ""))
            : ((q = b.decoder(O.slice(0, $), a.decoder, R, "key")),
              (C = e.maybeMap(
                o(O.slice($ + 1), b, r(E[q]) ? E[q].length : 0),
                function (x) {
                  return b.decoder(x, a.decoder, R, "value");
                },
              ))),
            C &&
              b.interpretNumericEntities &&
              R === "iso-8859-1" &&
              (C = v(String(C))),
            O.indexOf("[]=") > -1 && (C = r(C) ? [C] : C));
          var j = t.call(E, q);
          j && b.duplicates === "combine"
            ? (E[q] = e.combine(E[q], C))
            : (!j || b.duplicates === "last") && (E[q] = C);
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
            $ = parseInt(A, 10);
          !b.parseArrays && A === ""
            ? (S = { 0: s })
            : !isNaN($) &&
                R !== A &&
                String($) === A &&
                $ >= 0 &&
                b.parseArrays &&
                $ <= b.arrayLimit
              ? ((S = []), (S[$] = s))
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
    (dt = function (g, p) {
      var b = h(p);
      if (g === "" || g === null || typeof g > "u")
        return b.plainObjects ? { __proto__: null } : {};
      for (
        var E = typeof g == "string" ? m(g, b) : g,
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
    dt
  );
}
var ht, lo;
function Xa() {
  if (lo) return ht;
  lo = 1;
  var e = Ya(),
    t = Za(),
    r = Mt();
  return ((ht = { formats: r, parse: t, stringify: e }), ht);
}
var ei = Xa();
const ri = He(ei);
var ti = Sa;
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
var ni = /^([a-z0-9.+-]+:)/i,
  oi = /:[0-9]*$/,
  ai = /^(\/\/?(?!\/)[^?\s]*)(\?[^\s]*)?$/,
  ii = [
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
  si = ["{", "}", "|", "\\", "^", "`"].concat(ii),
  bt = ["'"].concat(si),
  fo = ["%", "/", "?", ";", "#"].concat(bt),
  uo = ["/", "?", "#"],
  li = 255,
  co = /^[+a-z0-9A-Z_-]{0,63}$/,
  fi = /^([+a-z0-9A-Z_-]{0,63})(.*)$/,
  ui = { javascript: !0, "javascript:": !0 },
  At = { javascript: !0, "javascript:": !0 },
  $e = {
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
  St = ri;
function qe(e, t, r) {
  if (e && typeof e == "object" && e instanceof he) return e;
  var a = new he();
  return (a.parse(e, t, r), a);
}
he.prototype.parse = function (e, t, r) {
  if (typeof e != "string")
    throw new TypeError("Parameter 'url' must be a string, not " + typeof e);
  var a = e.indexOf("?"),
    v = a !== -1 && a < e.indexOf("#") ? "?" : "#",
    o = e.split(v),
    i = /\\/g;
  ((o[0] = o[0].replace(i, "/")), (e = o.join(v)));
  var n = e;
  if (((n = n.trim()), !r && e.split("#").length === 1)) {
    var m = ai.exec(n);
    if (m)
      return (
        (this.path = n),
        (this.href = n),
        (this.pathname = m[1]),
        m[2]
          ? ((this.search = m[2]),
            t
              ? (this.query = St.parse(this.search.substr(1)))
              : (this.query = this.search.substr(1)))
          : t && ((this.search = ""), (this.query = {})),
        this
      );
  }
  var c = ni.exec(n);
  if (c) {
    c = c[0];
    var u = c.toLowerCase();
    ((this.protocol = u), (n = n.substr(c.length)));
  }
  if (r || c || n.match(/^\/\/[^@/]+@[^@/]+/)) {
    var h = n.substr(0, 2) === "//";
    h && !(c && At[c]) && ((n = n.substr(2)), (this.slashes = !0));
  }
  if (!At[c] && (h || (c && !$e[c]))) {
    for (var g = -1, p = 0; p < uo.length; p++) {
      var b = n.indexOf(uo[p]);
      b !== -1 && (g === -1 || b < g) && (g = b);
    }
    var E, l;
    (g === -1 ? (l = n.lastIndexOf("@")) : (l = n.lastIndexOf("@", g)),
      l !== -1 &&
        ((E = n.slice(0, l)),
        (n = n.slice(l + 1)),
        (this.auth = decodeURIComponent(E))),
      (g = -1));
    for (var p = 0; p < fo.length; p++) {
      var b = n.indexOf(fo[p]);
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
        if (S && !S.match(co)) {
          for (var R = "", O = 0, A = S.length; O < A; O++)
            S.charCodeAt(O) > 127 ? (R += "x") : (R += S[O]);
          if (!R.match(co)) {
            var $ = s.slice(0, p),
              q = s.slice(p + 1),
              C = S.match(fi);
            (C && ($.push(C[1]), q.unshift(C[2])),
              q.length && (n = "/" + q.join(".") + n),
              (this.hostname = $.join(".")));
            break;
          }
        }
      }
    (this.hostname.length > li
      ? (this.hostname = "")
      : (this.hostname = this.hostname.toLowerCase()),
      d || (this.hostname = ti.toASCII(this.hostname)));
    var j = this.port ? ":" + this.port : "",
      x = this.hostname || "";
    ((this.host = x + j),
      (this.href += this.host),
      d &&
        ((this.hostname = this.hostname.substr(1, this.hostname.length - 2)),
        n[0] !== "/" && (n = "/" + n)));
  }
  if (!ui[u])
    for (var p = 0, w = bt.length; p < w; p++) {
      var Y = bt[p];
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
        t && (this.query = St.parse(this.query)),
        (n = n.slice(0, ae)))
      : t && ((this.search = ""), (this.query = {})),
    n && (this.pathname = n),
    $e[u] && this.hostname && !this.pathname && (this.pathname = "/"),
    this.pathname || this.search)
  ) {
    var j = this.pathname || "",
      se = this.search || "";
    this.path = j + se;
  }
  return ((this.href = this.format()), this);
};
function ci(e) {
  return (
    typeof e == "string" && (e = qe(e)),
    e instanceof he ? e.format() : he.prototype.format.call(e)
  );
}
he.prototype.format = function () {
  var e = this.auth || "";
  e && ((e = encodeURIComponent(e)), (e = e.replace(/%3A/i, ":")), (e += "@"));
  var t = this.protocol || "",
    r = this.pathname || "",
    a = this.hash || "",
    v = !1,
    o = "";
  (this.host
    ? (v = e + this.host)
    : this.hostname &&
      ((v =
        e +
        (this.hostname.indexOf(":") === -1
          ? this.hostname
          : "[" + this.hostname + "]")),
      this.port && (v += ":" + this.port)),
    this.query &&
      typeof this.query == "object" &&
      Object.keys(this.query).length &&
      (o = St.stringify(this.query, {
        arrayFormat: "repeat",
        addQueryPrefix: !1,
      })));
  var i = this.search || (o && "?" + o) || "";
  return (
    t && t.substr(-1) !== ":" && (t += ":"),
    this.slashes || ((!t || $e[t]) && v !== !1)
      ? ((v = "//" + (v || "")), r && r.charAt(0) !== "/" && (r = "/" + r))
      : v || (v = ""),
    a && a.charAt(0) !== "#" && (a = "#" + a),
    i && i.charAt(0) !== "?" && (i = "?" + i),
    (r = r.replace(/[?#]/g, function (n) {
      return encodeURIComponent(n);
    })),
    (i = i.replace("#", "%23")),
    t + v + r + i + a
  );
};
function pi(e, t) {
  return qe(e, !1, !0).resolve(t);
}
he.prototype.resolve = function (e) {
  return this.resolveObject(qe(e, !1, !0)).format();
};
function yi(e, t) {
  return e ? qe(e, !1, !0).resolveObject(t) : t;
}
he.prototype.resolveObject = function (e) {
  if (typeof e == "string") {
    var t = new he();
    (t.parse(e, !1, !0), (e = t));
  }
  for (var r = new he(), a = Object.keys(this), v = 0; v < a.length; v++) {
    var o = a[v];
    r[o] = this[o];
  }
  if (((r.hash = e.hash), e.href === "")) return ((r.href = r.format()), r);
  if (e.slashes && !e.protocol) {
    for (var i = Object.keys(e), n = 0; n < i.length; n++) {
      var m = i[n];
      m !== "protocol" && (r[m] = e[m]);
    }
    return (
      $e[r.protocol] &&
        r.hostname &&
        !r.pathname &&
        ((r.pathname = "/"), (r.path = r.pathname)),
      (r.href = r.format()),
      r
    );
  }
  if (e.protocol && e.protocol !== r.protocol) {
    if (!$e[e.protocol]) {
      for (var c = Object.keys(e), u = 0; u < c.length; u++) {
        var h = c[u];
        r[h] = e[h];
      }
      return ((r.href = r.format()), r);
    }
    if (((r.protocol = e.protocol), !e.host && !At[e.protocol])) {
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
    S = r.protocol && !$e[r.protocol];
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
      $ = 0,
      q = s.length;
    q >= 0;
    q--
  )
    ((O = s[q]),
      O === "."
        ? s.splice(q, 1)
        : O === ".."
          ? (s.splice(q, 1), $++)
          : $ && (s.splice(q, 1), $--));
  if (!l && !d) for (; $--; $) s.unshift("..");
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
    t = oi.exec(e);
  (t &&
    ((t = t[0]),
    t !== ":" && (this.port = t.substr(1)),
    (e = e.substr(0, e.length - t.length))),
    e && (this.hostname = e));
};
var di = qe,
  hi = pi,
  Po = yi,
  vi = ci,
  mi = he;
function gi(e, t) {
  for (var r = 0, a = e.length - 1; a >= 0; a--) {
    var v = e[a];
    v === "."
      ? e.splice(a, 1)
      : v === ".."
        ? (e.splice(a, 1), r++)
        : r && (e.splice(a, 1), r--);
  }
  if (t) for (; r--; r) e.unshift("..");
  return e;
}
function bi() {
  for (var e = "", t = !1, r = arguments.length - 1; r >= -1 && !t; r--) {
    var a = r >= 0 ? arguments[r] : "/";
    if (typeof a != "string")
      throw new TypeError("Arguments to path.resolve must be strings");
    if (!a) continue;
    ((e = a + "/" + e), (t = a.charAt(0) === "/"));
  }
  return (
    (e = gi(
      Ai(e.split("/"), function (v) {
        return !!v;
      }),
      !t,
    ).join("/")),
    (t ? "/" : "") + e || "."
  );
}
function Ai(e, t) {
  if (e.filter) return e.filter(t);
  for (var r = [], a = 0; a < e.length; a++) t(e[a], a, e) && r.push(e[a]);
  return r;
}
var Oo = (function (e) {
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
  Si = vi,
  Ro = di,
  Io = hi,
  _o = mi,
  we = Oo.URL,
  To = Oo.URLSearchParams,
  Ei = /%/g,
  wi = /\\/g,
  Pi = /\n/g,
  Oi = /\r/g,
  Ri = /\t/g,
  Ii = 47;
function _i(e) {
  var t = e ?? null;
  return !!(t !== null && t?.href && t?.origin);
}
function Ti(e) {
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
function xi(e) {
  return (
    e.includes("%") && (e = e.replace(Ei, "%25")),
    e.includes("\\") && (e = e.replace(wi, "%5C")),
    e.includes(`
`) && (e = e.replace(Pi, "%0A")),
    e.includes("\r") && (e = e.replace(Oi, "%0D")),
    e.includes("	") && (e = e.replace(Ri, "%09")),
    e
  );
}
var xo = function (t) {
    if (typeof t > "u")
      throw new TypeError('The "domain" argument must be specified');
    return new we("http://" + t).hostname;
  },
  $o = function (t) {
    if (typeof t > "u")
      throw new TypeError('The "domain" argument must be specified');
    return new we("http://" + t).hostname;
  },
  No = function (t) {
    var r = new we("file://"),
      a = bi(t),
      v = t.charCodeAt(t.length - 1);
    return (
      v === Ii && a[a.length - 1] !== "/" && (a += "/"),
      (r.pathname = xi(a)),
      r
    );
  },
  Bt = function (t) {
    if (!_i(t) && typeof t != "string")
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
    return Ti(r);
  },
  Co = function (t, r) {
    var a, v, o, i;
    if ((r === void 0 && (r = {}), !(t instanceof we))) return Si(t);
    if (typeof r != "object" || r === null)
      throw new TypeError('The "options" argument must be of type object.');
    var n = (a = r.auth) != null ? a : !0,
      m = (v = r.fragment) != null ? v : !0,
      c = (o = r.search) != null ? o : !0;
    (i = r.unicode) != null;
    var u = new we(t.toString());
    return (
      n || ((u.username = ""), (u.password = "")),
      m || (u.hash = ""),
      c || (u.search = ""),
      u.toString()
    );
  },
  $i = {
    format: Co,
    parse: Ro,
    resolve: Io,
    resolveObject: Po,
    Url: _o,
    URL: we,
    URLSearchParams: To,
    domainToASCII: xo,
    domainToUnicode: $o,
    pathToFileURL: No,
    fileURLToPath: Bt,
  };
const rs = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      URL: we,
      URLSearchParams: To,
      Url: _o,
      default: $i,
      domainToASCII: xo,
      domainToUnicode: $o,
      fileURLToPath: Bt,
      format: Co,
      parse: Ro,
      pathToFileURL: No,
      resolve: Io,
      resolveObject: Po,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
var po = {};
const ts = !1,
  Ni = !0,
  ns = Ni,
  Ci = "config.json";
function Fi() {
  return po.BEEPER_USER_DATA_DIR
    ? po.BEEPER_USER_DATA_DIR
    : ze.join(Le.homedir(), "Library", "Application Support", "BeeperTexts");
}
function ki() {
  const e = Fi();
  return ze.join(e, Ci);
}
const os = globalThis.INITIAL_STATE?.userConfPath ?? ki(),
  Ye = +Le.release().split(".")[0],
  as = Ye >= 19,
  is = Ye >= 21,
  ss = Ye >= 22,
  Fo = Ye >= 25,
  ls = { x: Fo ? 12 : 18, y: 18 },
  fs = { x: 8, y: Fo ? 18 : 8 },
  Di = 140;
function Ui() {
  return (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" +
    ` AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${Di}.0.0.0 Safari/537.36`
  );
}
const qi = Ui(),
  Mi = "Beeper/3.110.1",
  us = qi?.replace(/ Chrome\/\d+\.\d+\.\d+\.\d+/, ` ${Mi}$&`),
  cs = "beeper://",
  ps =
    "<REDACTED_GOOGLE_OAUTH_CLIENT_ID>",
  ys = "com.automattic.beeper.siwa",
  ds = "help@beeper.com",
  hs = "mailto:help+feedback@beeper.com",
  vs =
    "https://help.beeper.com/en_US/quick-references/how-to-create-and-manage-merged-chats",
  ms =
    "https://help.beeper.com/using-on-device-chat-network-connections-in-beeper",
  Bi = "texts.com",
  ji = `https://${Bi}`,
  Ce = "https://www.beeper.com",
  gs = `${Ce}/terms-onboarding`,
  bs = `${Ce}/privacy`,
  As = `${Ce}/`,
  Ss = `${ji}/api/beeper`,
  Gi = "com.automattic.beeper.desktop",
  Es = "beeper-a8c-desktop",
  ws = "BEEPER-PRIVATE-API-PLEASE-DONT-USE",
  Ps = `${Ce}/download/android`,
  Os = `${Ce}/download/ios`,
  Rs = `${Ce}/download`,
  Is = "https://www.beeper.com/changelog/desktop",
  Li = Bt(new URL("..", import.meta.url)),
  Wi = Li,
  _s = Wi.replace(`app.asar${ze.sep}`, `app.asar.unpacked${ze.sep}`),
  Ts = "beeper_8a5da52ed126447d359e70c05721a8aa",
  xs = "!transcriptions:beeper.local",
  $s = "@room",
  Ns = [
    { id: "chatgpt", displayName: "ChatGPT", icon: "GPT" },
    { id: "apple-ai", displayName: "Apple Intelligence", icon: "APPLE" },
  ],
  Cs = {
    "gpt-5-mini": "GPT 5 mini",
    "gpt-5-nano": "GPT 5 nano",
    "gpt-4.1-mini": "GPT 4.1 mini",
  },
  Fs = "gpt-4.1-mini",
  ks = 330,
  Ds = 620,
  Us = 400,
  qs = 505,
  Ms = "add-account",
  Bs = 400,
  js = 560,
  Gs = 1200,
  Ls = 800,
  Ws = [
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
  zs = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2],
  Hs = [0, 30, 90, 120],
  Ks = Gi.endsWith(".nightly"),
  zi = Et.developer_mode || !1;
var Hi = {};
const Ki = Hi.FORCE_SENTRY != null || (!zi && !Et.sentry_disabled),
  { username: vt } = "userInfo" in Le ? Le.userInfo() : { username: "" },
  Vi = ia({ strict: !0 }),
  Te = (e) => {
    if (!e || typeof e != "string") return e;
    const r = (vt && vt.length > 2 ? e.replaceAll?.(vt, "$USER") : e)
      .replace(Vi, "<scrubbed_url>")
      .replace(
        /(iMessage|SMS|RCS);[-+];(chat)?\+?[\d -]+/g,
        "<scrubbed_imsg_id>",
      )
      .replace(/\d+@s\.whatsapp\.net/g, "<scrubbed_wa_id>")
      .replace(/\+\d[\d ().-]{5,}\d/g, "<scrubbed_phone>");
    return bo(r);
  },
  Ji = (e) =>
    e
      .replace(/(?:[A-Za-z]:\\|[/\\])[\s\S]*$/, "<path>")
      .replace(/\b\d+\b/g, "<n>")
      .trim()
      .slice(0, 120);
function Qi(e) {
  return (
    e &&
    (e.exception?.values?.forEach((t) => {
      (t.stacktrace?.frames?.forEach((r) => {
        delete r.module;
      }),
        t?.value && (t.value = Te(t.value)));
    }),
    typeof e.message == "string" && (e.message = Te(e.message)),
    typeof e.logentry?.message == "string" &&
      (e.logentry.message = Te(e.logentry.message)),
    e.breadcrumbs?.forEach((t) => {
      !t?.message ||
        (t.type === "ui" && t.category === "electron" && t.level === "info") ||
        (t.message = Te(t.message));
    }),
    e)
  );
}
function Yi(e) {
  const { data: t } = e;
  if (!t) return e;
  const r = { data: { ...t }, ...e };
  for (const a of Object.keys(t))
    typeof t[a] == "string" && (r.data[a] = Te(t[a]));
  return r;
}
const Vs = {
  enabled: Ki,
  dsn: fa,
  release: la.version,
  environment: "production",
  tracesSampleRate: 1,
  tracePropagationTargets: [
    /^https?:\/\/(localhost|127\.0\.0\.1)/,
    /^fileproxy:\/\//,
    /^https:\/\/(api\.)?beeper(-staging|-dev)?\.com/,
    /^https:\/\/(m\.)?texts\.com/,
    /^\//,
  ],
  beforeBreadcrumb: Yi,
  beforeSend: (e, t) => {
    const r = Qi(e),
      a = ha(t?.originalException);
    if (r && a) {
      const v = Te(a.cause);
      ((r.fingerprint = [
        "{{ default }}",
        "sdk-error",
        a.tag,
        a.method,
        v,
      ].filter(Boolean)),
        (r.tags = {
          ...r.tags,
          sdk_method: a.method,
          sdk_cause: v,
          ...(a.tag && { sdk_call: a.tag }),
        }));
      for (const o of r.exception?.values ?? [])
        o.type === "SDKError"
          ? (o.type = `SDKError(${a.method})`)
          : o.type === "RelayedError" &&
            a.tag &&
            (o.type = `RelayedError(${a.tag})`);
    } else if (r) {
      const v = r.exception?.values?.find(
        (o) => o.type === "SqliteError" && o.value,
      );
      v?.value && (r.fingerprint = ["{{ default }}", "sqlite", Ji(v.value)]);
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
  os as $,
  qs as A,
  Ts as B,
  ss as C,
  cs as D,
  ts as E,
  hs as F,
  ps as G,
  js as H,
  Os as I,
  Bs as J,
  fs as K,
  Ns as L,
  Zi as M,
  ls as N,
  vs as O,
  Ds as P,
  ks as Q,
  bs as R,
  _s as S,
  Es as T,
  $s as U,
  es as V,
  ds as W,
  gs as X,
  xs as Y,
  Ws as Z,
  qi as _,
  Us as a,
  As as a0,
  $i as a1,
  We as a2,
  Xo as a3,
  He as a4,
  Xi as a5,
  Le as a6,
  ze as a7,
  ma as a8,
  la as a9,
  Ho as aa,
  go as ab,
  va as ac,
  Te as ad,
  Vs as ae,
  ua as af,
  rs as ag,
  Et as ah,
  Ms as b,
  Hs as c,
  Cs as d,
  Ps as e,
  Ss as f,
  ys as g,
  Ls as h,
  Gs as i,
  Is as j,
  Ce as k,
  Rs as l,
  ws as m,
  ms as n,
  Li as o,
  Gi as p,
  Fs as q,
  zs as r,
  us as s,
  as as t,
  zi as u,
  ns as v,
  Ni as w,
  is as x,
  Ks as y,
  Fo as z,
};
//# sourceMappingURL=sentry-common-BxRELKId.js.map
