import {
  dk as i,
  aG as y,
  cv as Y,
  dj as q,
  ba as Q,
  cK as T,
} from "./App-CsJiApxN.js";
import { cD as B, aW as X } from "./matrix-util-Cr_UwXbj.js";
import "./sentry-common-BxRELKId.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
(function () {
  try {
    var t =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    t.SENTRY_RELEASE = { id: "4.3.209" };
    var e = new t.Error().stack;
    e &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[e] = "9de60842-c34d-4ae5-80fd-4cb147a4d928"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-9de60842-c34d-4ae5-80fd-4cb147a4d928"));
  } catch {}
})();
function M() {
  return (
    (M = Object.assign
      ? Object.assign.bind()
      : function (t) {
          for (var e = 1; e < arguments.length; e++) {
            var n = arguments[e];
            for (var o in n) ({}).hasOwnProperty.call(n, o) && (t[o] = n[o]);
          }
          return t;
        }),
    M.apply(null, arguments)
  );
}
function D(t, e) {
  if (t == null) return {};
  var n = {};
  for (var o in t)
    if ({}.hasOwnProperty.call(t, o)) {
      if (e.includes(o)) continue;
      n[o] = t[o];
    }
  return n;
}
function ee(t, e) {
  if (typeof t != "object" || !t) return t;
  var n = t[Symbol.toPrimitive];
  if (n !== void 0) {
    var o = n.call(t, e);
    if (typeof o != "object") return o;
    throw new TypeError("@@toPrimitive must return a primitive value.");
  }
  return String(t);
}
function te(t) {
  var e = ee(t, "string");
  return typeof e == "symbol" ? e : e + "";
}
const I = {
    NOT_LOADED: "NOT_LOADED",
    LOADING: "LOADING",
    LOADED: "LOADED",
    FAILED: "FAILED",
    AUTH_FAILURE: "AUTH_FAILURE",
  },
  ne = "https://maps.googleapis.com/maps/api/js";
class x {
  static async load(e, n) {
    var o;
    const s = e.libraries ? e.libraries.split(",") : [],
      r = this.serializeParams(e);
    (this.listeners.push(n),
      (o = window.google) != null && (o = o.maps) != null && o.importLibrary
        ? (this.serializedApiParams || (this.loadingStatus = I.LOADED),
          this.notifyLoadingStatusListeners())
        : ((this.serializedApiParams = r), this.initImportLibrary(e)),
      this.serializedApiParams &&
        this.serializedApiParams !== r &&
        console.warn(
          "[google-maps-api-loader] The maps API has already been loaded with different parameters and will not be loaded again. Refresh the page for new values to have effect.",
        ));
    const l = ["maps", ...s];
    await Promise.all(l.map((a) => google.maps.importLibrary(a)));
  }
  static serializeParams(e) {
    return [
      e.v,
      e.key,
      e.language,
      e.region,
      e.authReferrerPolicy,
      e.solutionChannel,
    ].join("/");
  }
  static initImportLibrary(e) {
    if (
      (window.google || (window.google = {}),
      window.google.maps || (window.google.maps = {}),
      window.google.maps.importLibrary)
    ) {
      console.error(
        "[google-maps-api-loader-internal]: initImportLibrary must only be called once",
      );
      return;
    }
    let n = null;
    const o = () =>
      n ||
      ((n = new Promise((s, r) => {
        var l;
        const a = document.createElement("script"),
          d = new URLSearchParams();
        for (const [f, u] of Object.entries(e)) {
          const g = f.replace(/[A-Z]/g, (h) => "_" + h[0].toLowerCase());
          d.set(g, String(u));
        }
        (d.set("loading", "async"),
          d.set("callback", "__googleMapsCallback__"),
          (a.async = !0),
          (a.src = ne + "?" + d.toString()),
          (a.nonce =
            ((l = document.querySelector("script[nonce]")) == null
              ? void 0
              : l.nonce) || ""),
          (a.onerror = () => {
            ((this.loadingStatus = I.FAILED),
              this.notifyLoadingStatusListeners(),
              r(new Error("The Google Maps JavaScript API could not load.")));
          }),
          (window.__googleMapsCallback__ = () => {
            ((this.loadingStatus = I.LOADED),
              this.notifyLoadingStatusListeners(),
              s());
          }),
          (window.gm_authFailure = () => {
            ((this.loadingStatus = I.AUTH_FAILURE),
              this.notifyLoadingStatusListeners());
          }),
          (this.loadingStatus = I.LOADING),
          this.notifyLoadingStatusListeners(),
          document.head.append(a));
      })),
      n);
    google.maps.importLibrary = (s) =>
      o().then(() => google.maps.importLibrary(s));
  }
  static notifyLoadingStatusListeners() {
    for (const e of this.listeners) e(this.loadingStatus);
  }
}
x.loadingStatus = I.NOT_LOADED;
x.serializedApiParams = void 0;
x.listeners = [];
const oe = ["onLoad", "onError", "apiKey", "version", "libraries"],
  re = ["children"],
  ae = "GMP_visgl_rgmlibrary_v1_default",
  P = y.createContext(null);
function se() {
  const [t, e] = i.useState({});
  return {
    mapInstances: t,
    addMapInstance: (r, l = "default") => {
      e((a) => M({}, a, { [l]: r }));
    },
    removeMapInstance: (r = "default") => {
      e((l) => D(l, [r].map(te)));
    },
    clearMapInstances: () => {
      e({});
    },
  };
}
function ie(t) {
  const { onLoad: e, onError: n, apiKey: o, version: s, libraries: r = [] } = t,
    l = D(t, oe),
    [a, d] = i.useState(x.loadingStatus),
    [f, u] = i.useReducer(
      (c, p) => (c[p.name] ? c : M({}, c, { [p.name]: p.value })),
      {},
    ),
    g = i.useMemo(() => r?.join(","), [r]),
    h = i.useMemo(
      () => JSON.stringify(M({ apiKey: o, version: s }, l)),
      [o, s, l],
    ),
    m = i.useCallback(
      async (c) => {
        var p;
        if (f[c]) return f[c];
        if (!((p = google) != null && (p = p.maps) != null && p.importLibrary))
          throw new Error(
            "[api-provider-internal] importLibrary was called before google.maps.importLibrary was defined.",
          );
        const E = await window.google.maps.importLibrary(c);
        return (u({ name: c, value: E }), E);
      },
      [f],
    );
  return (
    i.useEffect(() => {
      (async () => {
        try {
          const c = M({ key: o }, l);
          (s && (c.v = s),
            g?.length > 0 && (c.libraries = g),
            (c.channel === void 0 || c.channel < 0 || c.channel > 999) &&
              delete c.channel,
            c.solutionChannel === void 0
              ? (c.solutionChannel = ae)
              : c.solutionChannel === "" && delete c.solutionChannel,
            await x.load(c, (p) => d(p)));
          for (const p of ["core", "maps", ...r]) await m(p);
          e && e();
        } catch (c) {
          n
            ? n(c)
            : console.error(
                "<ApiProvider> failed to load the Google Maps JavaScript API",
                c,
              );
        }
      })();
    }, [o, g, h]),
    { status: a, loadedLibraries: f, importLibrary: m }
  );
}
const le = (t) => {
  const { children: e } = t,
    n = D(t, re),
    {
      mapInstances: o,
      addMapInstance: s,
      removeMapInstance: r,
      clearMapInstances: l,
    } = se(),
    { status: a, loadedLibraries: d, importLibrary: f } = ie(n),
    u = i.useMemo(
      () => ({
        mapInstances: o,
        addMapInstance: s,
        removeMapInstance: r,
        clearMapInstances: l,
        status: a,
        loadedLibraries: d,
        importLibrary: f,
      }),
      [o, s, r, l, a, d, f],
    );
  return y.createElement(P.Provider, { value: u }, e);
};
function ce(t, e) {
  for (const n of me) {
    const o = e[n],
      s = G[n];
    i.useEffect(() => {
      if (!t || !o) return;
      const r = google.maps.event.addListener(t, s, (l) => {
        o(ue(s, t, l));
      });
      return () => r.remove();
    }, [t, s, o]);
  }
}
function ue(t, e, n) {
  const o = { type: t, map: e, detail: {}, stoppable: !1, stop: () => {} };
  if (de.includes(t)) {
    const r = o,
      l = e.getCenter(),
      a = e.getZoom(),
      d = e.getHeading() || 0,
      f = e.getTilt() || 0,
      u = e.getBounds();
    return (
      (!l || !u || !Number.isFinite(a)) &&
        console.warn(
          "[createEvent] at least one of the values from the map returned undefined. This is not expected to happen. Please report an issue at https://github.com/visgl/react-google-maps/issues/new",
        ),
      (r.detail = {
        center: l?.toJSON() || { lat: 0, lng: 0 },
        zoom: a || 0,
        heading: d,
        tilt: f,
        bounds: u?.toJSON() || { north: 90, east: 180, south: -90, west: -180 },
      }),
      r
    );
  } else if (fe.includes(t)) {
    var s;
    if (!n)
      throw new Error("[createEvent] mouse events must provide a srcEvent");
    const r = o;
    return (
      (r.domEvent = n.domEvent),
      (r.stoppable = !0),
      (r.stop = () => n.stop()),
      (r.detail = {
        latLng: ((s = n.latLng) == null ? void 0 : s.toJSON()) || null,
        placeId: n.placeId,
      }),
      r
    );
  }
  return o;
}
const G = {
    onBoundsChanged: "bounds_changed",
    onCenterChanged: "center_changed",
    onClick: "click",
    onContextmenu: "contextmenu",
    onDblclick: "dblclick",
    onDrag: "drag",
    onDragend: "dragend",
    onDragstart: "dragstart",
    onHeadingChanged: "heading_changed",
    onIdle: "idle",
    onIsFractionalZoomEnabledChanged: "isfractionalzoomenabled_changed",
    onMapCapabilitiesChanged: "mapcapabilities_changed",
    onMapTypeIdChanged: "maptypeid_changed",
    onMousemove: "mousemove",
    onMouseout: "mouseout",
    onMouseover: "mouseover",
    onProjectionChanged: "projection_changed",
    onRenderingTypeChanged: "renderingtype_changed",
    onTilesLoaded: "tilesloaded",
    onTiltChanged: "tilt_changed",
    onZoomChanged: "zoom_changed",
    onCameraChanged: "bounds_changed",
  },
  de = [
    "bounds_changed",
    "center_changed",
    "heading_changed",
    "tilt_changed",
    "zoom_changed",
  ],
  fe = [
    "click",
    "contextmenu",
    "dblclick",
    "mousemove",
    "mouseout",
    "mouseover",
  ],
  me = Object.keys(G);
function ge(t, e) {
  const n = i.useRef(void 0);
  ((!n.current || !Y(e, n.current)) && (n.current = e),
    i.useEffect(t, n.current));
}
const pe = new Set([
  "backgroundColor",
  "clickableIcons",
  "controlSize",
  "disableDefaultUI",
  "disableDoubleClickZoom",
  "draggable",
  "draggableCursor",
  "draggingCursor",
  "fullscreenControl",
  "fullscreenControlOptions",
  "gestureHandling",
  "headingInteractionEnabled",
  "isFractionalZoomEnabled",
  "keyboardShortcuts",
  "mapTypeControl",
  "mapTypeControlOptions",
  "mapTypeId",
  "maxZoom",
  "minZoom",
  "noClear",
  "panControl",
  "panControlOptions",
  "restriction",
  "rotateControl",
  "rotateControlOptions",
  "scaleControl",
  "scaleControlOptions",
  "scrollwheel",
  "streetView",
  "streetViewControl",
  "streetViewControlOptions",
  "styles",
  "tiltInteractionEnabled",
  "zoomControl",
  "zoomControlOptions",
]);
function he(t, e) {
  const n = {},
    o = Object.keys(e);
  for (const s of o) pe.has(s) && (n[s] = e[s]);
  ge(() => {
    t && t.setOptions(n);
  }, [n]);
}
function Z() {
  var t;
  return ((t = i.useContext(P)) == null ? void 0 : t.status) || I.NOT_LOADED;
}
function ve(t, e) {
  const { viewport: n, viewState: o } = e,
    s = !!n;
  return (
    i.useLayoutEffect(() => {
      if (!t || !o) return;
      const { latitude: r, longitude: l, bearing: a, pitch: d, zoom: f } = o;
      t.moveCamera({
        center: { lat: r, lng: l },
        heading: a,
        tilt: d,
        zoom: f + 1,
      });
    }, [t, o]),
    s
  );
}
function ye(t) {
  return !t || typeof t != "object" || !("lat" in t && "lng" in t)
    ? !1
    : Number.isFinite(t.lat) && Number.isFinite(t.lng);
}
function $(t) {
  return ye(t) ? t : t.toJSON();
}
function be(t, e, n) {
  const o = n.center ? $(n.center) : null;
  let s = null,
    r = null;
  o &&
    Number.isFinite(o.lat) &&
    Number.isFinite(o.lng) &&
    ((s = o.lat), (r = o.lng));
  const l = Number.isFinite(n.zoom) ? n.zoom : null,
    a = Number.isFinite(n.heading) ? n.heading : null,
    d = Number.isFinite(n.tilt) ? n.tilt : null;
  i.useLayoutEffect(() => {
    if (!t) return;
    const f = {};
    let u = !1;
    (s !== null &&
      r !== null &&
      (e.current.center.lat !== s || e.current.center.lng !== r) &&
      ((f.center = { lat: s, lng: r }), (u = !0)),
      l !== null && e.current.zoom !== l && ((f.zoom = l), (u = !0)),
      a !== null && e.current.heading !== a && ((f.heading = a), (u = !0)),
      d !== null && e.current.tilt !== d && ((f.tilt = d), (u = !0)),
      u && t.moveCamera(f));
  });
}
const Ee = () => {
  const t = {
    position: "absolute",
    top: 0,
    left: 0,
    bottom: 0,
    right: 0,
    zIndex: 999,
    display: "flex",
    flexFlow: "column nowrap",
    textAlign: "center",
    justifyContent: "center",
    fontSize: ".8rem",
    color: "rgba(0,0,0,0.6)",
    background: "#dddddd",
    padding: "1rem 1.5rem",
  };
  return y.createElement(
    "div",
    { style: t },
    y.createElement("h2", null, "Error: AuthFailure"),
    y.createElement(
      "p",
      null,
      "A problem with your API key prevents the map from rendering correctly. Please make sure the value of the ",
      y.createElement("code", null, "APIProvider.apiKey"),
      " prop is correct. Check the error-message in the console for further details.",
    ),
  );
};
function Le() {
  const [t, e] = i.useState(null),
    n = i.useCallback((o) => e(o), [e]);
  return [t, n];
}
function J() {
  return Z() === I.LOADED;
}
function Ce() {
  const [, t] = i.useReducer((e) => e + 1, 0);
  return t;
}
function Me(t, e) {
  const n = t.getCenter(),
    o = t.getZoom(),
    s = t.getHeading() || 0,
    r = t.getTilt() || 0,
    l = t.getBounds();
  ((!n || !l || !Number.isFinite(o)) &&
    console.warn(
      "[useTrackedCameraState] at least one of the values from the map returned undefined. This is not expected to happen. Please report an issue at https://github.com/visgl/react-google-maps/issues/new",
    ),
    Object.assign(e.current, {
      center: n?.toJSON() || { lat: 0, lng: 0 },
      zoom: o || 0,
      heading: s,
      tilt: r,
    }));
}
function Se(t) {
  const e = Ce(),
    n = i.useRef({ center: { lat: 0, lng: 0 }, heading: 0, tilt: 0, zoom: 0 });
  return (
    i.useEffect(() => {
      if (!t) return;
      const o = google.maps.event.addListener(t, "bounds_changed", () => {
        (Me(t, n), e());
      });
      return () => o.remove();
    }, [t, e]),
    n
  );
}
const we = [
    "id",
    "defaultBounds",
    "defaultCenter",
    "defaultZoom",
    "defaultHeading",
    "defaultTilt",
    "reuseMaps",
    "renderingType",
    "colorScheme",
  ],
  Ie = ["padding"];
class F {
  static has(e) {
    return this.entries[e] && this.entries[e].length > 0;
  }
  static pop(e) {
    return (this.entries[e] && this.entries[e].pop()) || null;
  }
  static push(e, n) {
    (this.entries[e] || (this.entries[e] = []), this.entries[e].push(n));
  }
}
F.entries = {};
function _e(t, e) {
  const n = J(),
    [o, s] = i.useState(null),
    [r, l] = Le(),
    a = Se(o),
    {
      id: d,
      defaultBounds: f,
      defaultCenter: u,
      defaultZoom: g,
      defaultHeading: h,
      defaultTilt: m,
      reuseMaps: c,
      renderingType: p,
      colorScheme: E,
    } = t,
    v = D(t, we),
    S = t.zoom !== void 0 || t.defaultZoom !== void 0,
    _ = t.center !== void 0 || t.defaultCenter !== void 0;
  (!f &&
    (!S || !_) &&
    console.warn(
      "<Map> component is missing configuration. You have to provide zoom and center (via the `zoom`/`defaultZoom` and `center`/`defaultCenter` props) or specify the region to show using `defaultBounds`. See https://visgl.github.io/react-google-maps/docs/api-reference/components/map#required",
    ),
    !v.center && u && (v.center = u),
    !v.zoom && Number.isFinite(g) && (v.zoom = g),
    !v.heading && Number.isFinite(h) && (v.heading = h),
    !v.tilt && Number.isFinite(m) && (v.tilt = m));
  for (const L of Object.keys(v)) v[L] === void 0 && delete v[L];
  const O = i.useRef(void 0);
  return (
    i.useEffect(() => {
      if (!r || !n) return;
      const { addMapInstance: L, removeMapInstance: C } = e,
        { mapId: w } = t,
        A = `${w || "default"}:${p || "default"}:${E || "LIGHT"}`;
      let k, b;
      if (
        (c && F.has(A)
          ? ((b = F.pop(A)),
            (k = b.getDiv()),
            r.appendChild(k),
            b.setOptions(v),
            setTimeout(() => b.setCenter(b.getCenter()), 0))
          : ((k = document.createElement("div")),
            (k.style.height = "100%"),
            r.appendChild(k),
            (b = new google.maps.Map(
              k,
              M(
                {},
                v,
                p ? { renderingType: p } : {},
                E ? { colorScheme: E } : {},
              ),
            ))),
        s(b),
        L(b, d),
        f)
      ) {
        const { padding: R } = f,
          U = D(f, Ie);
        b.fitBounds(U, R);
      } else
        (!S || !_) &&
          b.fitBounds({ east: 180, west: -180, south: -90, north: 90 });
      if (O.current) {
        const { mapId: R, cameraState: U } = O.current;
        R !== w && b.setOptions(U);
      }
      return () => {
        ((O.current = { mapId: w, cameraState: a.current }),
          k.remove(),
          c ? F.push(A, b) : google.maps.event.clearInstanceListeners(b),
          s(null),
          C(d));
      };
    }, [r, n, d, t.mapId, t.renderingType, t.colorScheme]),
    [o, l, a]
  );
}
const K = y.createContext(null),
  Oe = { FOLLOW_SYSTEM: "FOLLOW_SYSTEM" },
  V = (t) => {
    const { children: e, id: n, className: o, style: s } = t,
      r = i.useContext(P),
      l = Z();
    if (!r)
      throw new Error(
        "<Map> can only be used inside an <ApiProvider> component.",
      );
    const [a, d, f] = _e(t, r);
    (be(a, f, t), ce(a, t), he(a, t));
    const u = ve(a, t),
      g = !!t.controlled;
    i.useEffect(() => {
      if (a)
        return (
          u && a.setOptions({ disableDefaultUI: !0 }),
          (u || g) &&
            a.setOptions({ gestureHandling: "none", keyboardShortcuts: !1 }),
          () => {
            a.setOptions({
              gestureHandling: t.gestureHandling,
              keyboardShortcuts: t.keyboardShortcuts,
            });
          }
        );
    }, [a, u, g, t.gestureHandling, t.keyboardShortcuts]);
    const h = t.center ? $(t.center) : null;
    let m = null,
      c = null;
    h &&
      Number.isFinite(h.lat) &&
      Number.isFinite(h.lng) &&
      ((m = h.lat), (c = h.lng));
    const p = i.useMemo(() => {
      var S, _, O, L, C;
      return {
        center: { lat: (S = m) != null ? S : 0, lng: (_ = c) != null ? _ : 0 },
        zoom: (O = t.zoom) != null ? O : 0,
        heading: (L = t.heading) != null ? L : 0,
        tilt: (C = t.tilt) != null ? C : 0,
      };
    }, [m, c, t.zoom, t.heading, t.tilt]);
    i.useLayoutEffect(() => {
      if (!a || !g) return;
      a.moveCamera(p);
      const S = a.addListener("bounds_changed", () => {
        a.moveCamera(p);
      });
      return () => S.remove();
    }, [a, g, p]);
    const E = i.useMemo(
        () =>
          M(
            {
              width: "100%",
              height: "100%",
              position: "relative",
              zIndex: u ? -1 : 0,
            },
            s,
          ),
        [s, u],
      ),
      v = i.useMemo(() => ({ map: a }), [a]);
    return l === I.AUTH_FAILURE
      ? y.createElement(
          "div",
          { style: M({ position: "relative" }, o ? {} : E), className: o },
          y.createElement(Ee, null),
        )
      : y.createElement(
          "div",
          M(
            {
              ref: d,
              "data-testid": "map",
              style: o ? void 0 : E,
              className: o,
            },
            n ? { id: n } : {},
          ),
          a ? y.createElement(K.Provider, { value: v }, e) : null,
        );
  };
V.deckGLViewProps = !0;
const H = new Set();
function ke(...t) {
  const e = JSON.stringify(t);
  H.has(e) || (H.add(e), console.error(...t));
}
const W = (t = null) => {
  const e = i.useContext(P),
    { map: n } = i.useContext(K) || {};
  if (e === null)
    return (
      ke(
        "useMap(): failed to retrieve APIProviderContext. Make sure that the <APIProvider> component exists and that the component you are calling `useMap()` from is a sibling of the <APIProvider>.",
      ),
      null
    );
  const { mapInstances: o } = e;
  return t !== null ? o[t] || null : n || o.default || null;
};
function Ae(t) {
  const e = J(),
    n = i.useContext(P);
  return (
    i.useEffect(() => {
      !e || !n || n.importLibrary(t);
    }, [e, n, t]),
    n?.loadedLibraries[t] || null
  );
}
function N(t, e, n) {
  i.useEffect(() => {
    if (!t || !e || !n) return;
    const o = google.maps.event.addListener(t, e, n);
    return () => o.remove();
  }, [t, e, n]);
}
function z(t, e, n) {
  i.useEffect(() => {
    t && (t[e] = n);
  }, [t, e, n]);
}
function j(t, e, n) {
  i.useEffect(() => {
    if (!(!t || !e || !n))
      return (t.addEventListener(e, n), () => t.removeEventListener(e, n));
  }, [t, e, n]);
}
function De(t) {
  return t.nodeType === Node.ELEMENT_NODE;
}
const xe = y.createContext(null),
  Pe = { BOTTOM: ["50%", "100%"] },
  Te = ({ children: t, styles: e, className: n, anchorPoint: o }) => {
    const [s, r] = o ?? Pe.BOTTOM,
      l = `translate(50%, 100%) translate(-${s}, -${r})`;
    return y.createElement(
      "div",
      { style: { transform: l } },
      y.createElement("div", { className: n, style: e }, t),
    );
  };
function Ne(t) {
  const [e, n] = i.useState(null),
    [o, s] = i.useState(null),
    r = W(),
    l = Ae("marker"),
    {
      children: a,
      onClick: d,
      className: f,
      onMouseEnter: u,
      onMouseLeave: g,
      onDrag: h,
      onDragStart: m,
      onDragEnd: c,
      collisionBehavior: p,
      clickable: E,
      draggable: v,
      position: S,
      title: _,
      zIndex: O,
    } = t,
    L = i.Children.count(a);
  return (
    i.useEffect(() => {
      if (!r || !l) return;
      const C = new l.AdvancedMarkerElement();
      ((C.map = r), n(C));
      let w = null;
      return (
        L > 0 &&
          ((w = document.createElement("div")),
          (w.isCustomMarker = !0),
          (C.content = w),
          s(w)),
        () => {
          var A;
          ((C.map = null), (A = w) == null || A.remove(), n(null), s(null));
        }
      );
    }, [r, l, L]),
    i.useEffect(() => {
      !e || !e.content || L > 0 || (e.content.className = f || "");
    }, [e, f, L]),
    z(e, "position", S),
    z(e, "title", _ ?? ""),
    z(e, "zIndex", O),
    z(e, "collisionBehavior", p),
    i.useEffect(() => {
      e &&
        (v !== void 0
          ? (e.gmpDraggable = v)
          : h || m || c
            ? (e.gmpDraggable = !0)
            : (e.gmpDraggable = !1));
    }, [e, v, h, c, m]),
    i.useEffect(() => {
      if (!e) return;
      const C = E !== void 0 || !!d || !!u || !!g;
      ((e.gmpClickable = C),
        C &&
          e != null &&
          e.content &&
          De(e.content) &&
          ((e.content.style.pointerEvents = "none"),
          e.content.firstElementChild &&
            (e.content.firstElementChild.style.pointerEvents = "all")));
    }, [e, E, d, u, g]),
    N(e, "click", d),
    N(e, "drag", h),
    N(e, "dragstart", m),
    N(e, "dragend", c),
    j(e?.element, "mouseenter", u),
    j(e?.element, "mouseleave", g),
    [e, o]
  );
}
i.forwardRef((t, e) => {
  const { children: n, style: o, className: s, anchorPoint: r } = t,
    [l, a] = Ne(t),
    d = i.useMemo(() => (l ? { marker: l } : null), [l]);
  return (
    i.useImperativeHandle(e, () => l, [l]),
    a
      ? y.createElement(
          xe.Provider,
          { value: d },
          q.createPortal(
            y.createElement(Te, { anchorPoint: r, styles: o, className: s }, n),
            a,
          ),
        )
      : null
  );
});
const ze = [
  "onClick",
  "onDrag",
  "onDragStart",
  "onDragEnd",
  "onMouseOver",
  "onMouseOut",
];
function Fe(t) {
  const [e, n] = i.useState(null),
    o = W(),
    {
      onClick: s,
      onDrag: r,
      onDragStart: l,
      onDragEnd: a,
      onMouseOver: d,
      onMouseOut: f,
    } = t,
    u = D(t, ze),
    { position: g, draggable: h } = u;
  return (
    i.useEffect(() => {
      if (!o) {
        o === void 0 &&
          console.error("<Marker> has to be inside a Map component.");
        return;
      }
      const m = new google.maps.Marker(u);
      return (
        m.setMap(o),
        n(m),
        () => {
          (m.setMap(null), n(null));
        }
      );
    }, [o]),
    i.useEffect(() => {
      if (!e) return;
      const m = e,
        c = google.maps.event;
      return (
        s && c.addListener(m, "click", s),
        r && c.addListener(m, "drag", r),
        l && c.addListener(m, "dragstart", l),
        a && c.addListener(m, "dragend", a),
        d && c.addListener(m, "mouseover", d),
        f && c.addListener(m, "mouseout", f),
        e.setDraggable(!!h),
        () => {
          c.clearInstanceListeners(m);
        }
      );
    }, [e, h, s, r, l, a, d, f]),
    i.useEffect(() => {
      e && u && e.setOptions(u);
    }, [e, u]),
    i.useEffect(() => {
      h || !g || !e || e.setPosition(g);
    }, [h, g, e]),
    e
  );
}
const Re = i.forwardRef((t, e) => {
    const n = Fe(t);
    return (
      i.useImperativeHandle(e, () => n, [n]),
      y.createElement(y.Fragment, null)
    );
  }),
  Ue = "Location-module__wrapper",
  Be = { wrapper: Ue },
  Ye = ({ message: t }) => {
    const { latitude: e, longitude: n } = t?.extra?.location ?? {},
      o = i.useContext(Q),
      { viewportSize: s } = o,
      r =
        B.localPrefsStore.nativeThemeSource === "system"
          ? Oe.FOLLOW_SYSTEM
          : B.localPrefsStore.nativeThemeSource.toUpperCase(),
      l = X(s, { width: 560, height: 320 });
    if (!(e && n)) return null;
    const a = { lat: Number(e), lng: Number(n) };
    return T.jsx("div", {
      className: Be.wrapper,
      style: l,
      "data-sentry-component": "Location",
      "data-sentry-source-file": "Location.tsx",
      children: T.jsx(le, {
        apiKey: "AIzaSyADajjJIohTu1Soxz9vKWF9tfE8p7R43rQ",
        "data-sentry-element": "APIProvider",
        "data-sentry-source-file": "Location.tsx",
        children: T.jsx(V, {
          defaultCenter: a,
          defaultZoom: 16,
          gestureHandling: "greedy",
          disableDefaultUI: !0,
          colorScheme: r,
          "data-sentry-element": "Map",
          "data-sentry-source-file": "Location.tsx",
          children: T.jsx(Re, {
            position: a,
            "data-sentry-element": "Marker",
            "data-sentry-source-file": "Location.tsx",
          }),
        }),
      }),
    });
  };
export { Ye as Location };
//# sourceMappingURL=index-DbeHZPIl.js.map
