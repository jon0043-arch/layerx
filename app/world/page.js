"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import "./world.css";

const LOCAL_KEY = "layerx.layers.v1";
const SAVED_KEY = "layerx.saved.v1";
const distanceMeters = (a, b) => {
  const rad = Math.PI / 180;
  const dLat = (b.latitude - a.latitude) * rad;
  const dLon = (b.longitude - a.longitude) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dLon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
};
const formatDistance = (n) => n < 1000 ? Math.round(n) + " M" : (n / 1000).toFixed(1) + " KM";
const readJSON = (key, fallback) => {
  try { return JSON.parse(localStorage.getItem(key) || "null") ?? fallback; } catch { return fallback; }
};

export default function LayerXWorld() {
  const [tab, setTab] = useState("scan");
  const [cameraOn, setCameraOn] = useState(false);
  const [cameraError, setCameraError] = useState("");
  const [position, setPosition] = useState(null);
  const [locationError, setLocationError] = useState("");
  const [localLayers, setLocalLayers] = useState([]);
  const [remoteLayers, setRemoteLayers] = useState([]);
  const [savedIds, setSavedIds] = useState([]);
  const [selected, setSelected] = useState(null);
  const [mode, setMode] = useState("loading");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [form, setForm] = useState({ title: "", message: "", creator: "", code: "" });
  const videoRef = useRef(null);
  const streamRef = useRef(null);

  useEffect(() => {
    setLocalLayers(readJSON(LOCAL_KEY, []));
    setSavedIds(readJSON(SAVED_KEY, []));
    const code = sessionStorage.getItem("layerx.access") || "";
    setForm(f => ({ ...f, code }));
  }, []);

  useEffect(() => {
    if (!cameraOn || tab !== "scan") return;
    let cancelled = false;
    if (!navigator.mediaDevices?.getUserMedia) {
      setCameraError("CAMERA REQUIRES A SECURE CONNECTION AND SUPPORTED BROWSER");
      setCameraOn(false);
      return;
    }
    navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" } }, audio: false })
      .then(stream => {
        if (cancelled) { stream.getTracks().forEach(t => t.stop()); return; }
        streamRef.current = stream;
        if (videoRef.current) { videoRef.current.srcObject = stream; videoRef.current.play().catch(() => {}); }
        setCameraError("");
      })
      .catch(() => { setCameraError("CAMERA ACCESS DENIED OR UNAVAILABLE"); setCameraOn(false); });
    return () => {
      cancelled = true;
      streamRef.current?.getTracks().forEach(t => t.stop());
      streamRef.current = null;
    };
  }, [cameraOn, tab]);

  const locate = useCallback(() => {
    if (!navigator.geolocation) { setLocationError("LOCATION NOT AVAILABLE"); return; }
    setLocationError("");
    navigator.geolocation.getCurrentPosition(
      p => setPosition({ latitude: p.coords.latitude, longitude: p.coords.longitude, accuracy: p.coords.accuracy }),
      () => setLocationError("ENABLE LOCATION PERMISSION TO DISCOVER NEARBY LAYERS"),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 15000 }
    );
  }, []);

  const refresh = useCallback(async () => {
    if (!position) { setMode("local"); return; }
    try {
      const response = await fetch("/api/layers?lat=" + position.latitude + "&lon=" + position.longitude, { cache: "no-store" });
      if (!response.ok) throw new Error("network");
      const data = await response.json();
      setRemoteLayers((data.layers || []).map(l => ({ ...l, source: "shared" })));
      setMode(data.mode === "live" ? "live" : "local");
    } catch { setMode("local"); }
  }, [position]);

  useEffect(() => { refresh(); }, [refresh]);

  const layers = useMemo(() => {
    const merged = new Map();
    [...localLayers, ...remoteLayers].forEach(l => merged.set(l.id, l));
    return [...merged.values()]
      .map(l => ({ ...l, meters: position ? distanceMeters(position, l) : null }))
      .filter(l => !position || l.meters <= 1500)
      .sort((a, b) => (a.meters ?? 0) - (b.meters ?? 0));
  }, [localLayers, remoteLayers, position]);

  const active = layers.find(l => l.id === selected) || layers[0] || null;
  const saveLayer = id => {
    setSavedIds(old => {
      const next = old.includes(id) ? old.filter(x => x !== id) : [...old, id];
      localStorage.setItem(SAVED_KEY, JSON.stringify(next));
      return next;
    });
  };
  const updateForm = (key, value) => setForm(f => ({ ...f, [key]: value }));

  const publish = async e => {
    e.preventDefault();
    if (!position) { setNotice("ALLOW LOCATION ACCESS BEFORE PLACING A LAYER"); return; }
    if (form.title.trim().length < 2 || form.message.trim().length < 2) return;
    setBusy(true);
    setNotice("");
    const draft = {
      title: form.title.trim().slice(0, 60),
      message: form.message.trim().slice(0, 280),
      creator: (form.creator.trim() || "ANONYMOUS").slice(0, 32),
      latitude: position.latitude, longitude: position.longitude
    };
    let created = null;
    if (mode === "live" && form.code.trim()) {
      try {
        const response = await fetch("/api/layers", {
          method: "POST",
          headers: { "Content-Type": "application/json", "x-layerx-create-code": form.code.trim() },
          body: JSON.stringify(draft)
        });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || "PUBLISH FAILED");
        created = { ...data.layer, source: "shared" };
        setRemoteLayers(old => [created, ...old]);
        sessionStorage.setItem("layerx.access", form.code.trim());
        setNotice("LAYER PUBLISHED. OTHER DEVICES CAN DISCOVER IT NEARBY.");
      } catch (error) {
        setNotice(error.message || "COULD NOT PUBLISH. CHECK YOUR ACCESS CODE.");
        setBusy(false);
        return;
      }
    } else {
      created = { ...draft, id: crypto.randomUUID(), created_at: new Date().toISOString(), source: "local" };
      setLocalLayers(old => {
        const next = [created, ...old];
        localStorage.setItem(LOCAL_KEY, JSON.stringify(next));
        return next;
      });
      setNotice("SAVED TO THIS DEVICE. CONNECT SHARED STORAGE TO PUBLISH FOR OTHERS.");
    }
    setSelected(created.id);
    setForm(f => ({ ...f, title: "", message: "" }));
    setBusy(false);
    setTab("scan");
  };

  const share = async l => {
    if (l.source !== "shared") { setNotice("THIS LAYER IS LOCAL TO YOUR DEVICE"); return; }
    const url = window.location.origin + "/world?layer=" + encodeURIComponent(l.id);
    try {
      if (navigator.share) await navigator.share({ title: l.title, url });
      else { await navigator.clipboard.writeText(url); setNotice("DISCOVERY LINK COPIED"); }
    } catch {}
  };

  useEffect(() => {
    const requested = new URLSearchParams(window.location.search).get("layer");
    if (requested && layers.some(l => l.id === requested)) setSelected(requested);
  }, [layers]);

  const [mapExpanded, setMapExpanded] = useState(false);

  return (
    <main className="lx-world">
      <header className="lx-top">
        <a href="/" className="lx-wordmark">LAYER <b>X</b></a>
        <div className="lx-topright"><span className="lx-pulse" /> FIELD TEST / 001</div>
      </header>

      <div className="lx-headline">
        <div className="lx-kicker">THE WORLD HAS ANOTHER LAYER.</div>
        <h1>{tab === "scan" ? "SEE THE INVISIBLE." : tab === "discover" ? "WHAT'S OUT THERE." : tab === "drop" ? "LEAVE YOUR MARK." : "YOUR COLLECTION."}</h1>
        <p>{tab === "scan" ? "Point your camera. Find something left behind." : tab === "drop" ? "Attach a message to the place where you're standing." : "Digital traces attached to real places."}</p>
      </div>

      {tab === "scan" && (
        <section className={"lx-viewport " + (cameraOn ? "lx-camera-on" : "")}>
          {cameraOn && <video ref={videoRef} autoPlay muted playsInline className="lx-video" />}
          {!cameraOn && <div className="lx-ambient"><div className="lx-orb" /></div>}
          <div className="lx-corner top-left" /><div className="lx-corner top-right" />
          <div className="lx-corner bottom-left" /><div className="lx-corner bottom-right" />
          <div className="lx-vtop"><span>LIVE SCAN</span><span>{position ? "GPS ±" + Math.round(position.accuracy) + "M" : "LOCATION OFFLINE"}</span></div>
          <div className="lx-crosshair"><span /><span /></div>
          {active && (
            <div className="lx-signal" role="button" tabIndex={0} onClick={() => setMapExpanded(true)} onKeyDown={e => e.key === "Enter" && setMapExpanded(true)}>
              <div className="lx-signal-eyebrow">◆ SIGNAL DETECTED / {active.meters !== null ? formatDistance(active.meters) : "LOCAL"}</div>
              <strong>{active.title}</strong>
              <p>{active.message}</p>
              <div className="lx-signal-foot">LEFT BY {active.creator || "ANONYMOUS"} <span>VIEW DETAILS ↗</span></div>
            </div>
          )}
          {!active && <div className="lx-empty"><div className="lx-empty-star">✳</div><strong>NOTHING HERE. YET.</strong><span>BE THE FIRST TO LEAVE A LAYER.</span></div>}
          <div className="lx-vbottom"><span>GPS-BASED PREVIEW · NOT PRECISE AR ANCHORING</span><span>{layers.length.toString().padStart(2,"0")} SIGNALS</span></div>
          {!cameraOn && <button className="lx-enable" onClick={() => setCameraOn(true)}>ENABLE CAMERA <span>↗</span></button>}
          {!!cameraError && <div className="lx-error">{cameraError}</div>}
        </section>
      )}

      {tab === "discover" && (
        <section className="lx-list">
          {layers.length === 0 ? <div className="lx-zero"><span>000</span><h2>NO SIGNALS FOUND.</h2><p>Every place begins empty. Someone has to leave the first Layer.</p><button onClick={() => setTab("drop")}>CREATE THE FIRST ONE ↗</button></div> :
          layers.map(l => <button key={l.id} className="lx-result" onClick={() => { setSelected(l.id); setMapExpanded(true); }}>
            <div className="lx-result-index">{l.source === "shared" ? "◈" : "◇"}</div>
            <div><strong>{l.title}</strong><p>{l.message}</p><span>BY {l.creator || "ANONYMOUS"} · {l.source === "shared" ? "PUBLIC" : "THIS DEVICE"}</span></div>
            <aside>{l.meters !== null ? formatDistance(l.meters) : "LOCAL"}<span>↗</span></aside>
          </button>)}
        </section>
      )}

      {tab === "drop" && (
        <section className="lx-compose">
          <div className="lx-compose-no">01 / MAKE A MARK</div>
          <form onSubmit={publish}>
            <label>GIVE YOUR LAYER A NAME <input maxLength={60} required minLength={2} placeholder="SOMETHING IS HERE" value={form.title} onChange={e => updateForm("title",e.target.value)} /></label>
            <label>WHAT WILL PEOPLE DISCOVER? <textarea required maxLength={280} minLength={2} rows={4} placeholder="Leave a thought, a memory, a secret, a story..." value={form.message} onChange={e => updateForm("message", e.target.value)} /></label>
            <label>YOUR SIGNATURE <input maxLength={32} placeholder="ANONYMOUS" value={form.creator} onChange={e => updateForm("creator", e.target.value)} /></label>
            {mode === "live" && <label>FIELD TEST PUBLISH CODE (OPTIONAL) <input type="password" autoComplete="off" placeholder="FOR SHARED LAYERS" value={form.code} onChange={e => updateForm("code", e.target.value)} /></label>}
            <div className="lx-location-line"><span>LOCATION ANCHOR</span><strong>{position ? position.latitude.toFixed(5) + "°, " + position.longitude.toFixed(5) + "°" : "NOT ACQUIRED"}</strong></div>
            <button type="button" className="lx-locate-inline" onClick={locate}>{position ? "↻ UPDATE POSITION" : "⌖ ENABLE LOCATION"}</button>
            <button type="submit" className="lx-primary" disabled={busy || !position}>{busy ? "PLACING..." : "DROP LAYER ↗"}</button>
          </form>
        </section>
      )}

      {tab === "saved" && (
        <section className="lx-list">
          {layers.filter(l => savedIds.includes(l.id)).length === 0
            ? <div className="lx-zero"><span>✳</span><h2>NOTHING SAVED.</h2><p>Open a signal and bookmark it to find it here.</p></div>
            : layers.filter(l => savedIds.includes(l.id)).map(l => <button key={l.id} className="lx-result" onClick={() => { setSelected(l.id); setMapExpanded(true); }}><div className="lx-result-index">◆</div><div><strong>{l.title}</strong><p>{l.message}</p></div><aside>↗</aside></button>)}
        </section>
      )}

      <div className="lx-status">
        <button onClick={locate} className={position ? "ready" : ""}>⌖ {position ? "LOCATION ACTIVE" : "ENABLE LOCATION"}</button>
        <span className="lx-status-dot">·</span>
        <span>{mode === "live" ? "SHARED NETWORK ONLINE" : "LOCAL FIELD MODE"}</span>
        <button onClick={refresh}>↻</button>
      </div>
      {!!locationError && <div className="lx-alert">{locationError}</div>}
      {!!notice && <button className="lx-alert" onClick={() => setNotice("")}>{notice} ×</button>}
      <nav className="lx-nav" aria-label="World navigation">
        {[["scan", "⌖", "SCAN"], ["discover", "▦", "DISCOVER"], ["drop", "+", "DROP"], ["saved", "◇", "SAVED"]].map(([id, glyph, label]) =>
          <button key={id} className={tab === id ? "active" : ""} onClick={() => { setTab(id); setMapExpanded(false); }}><span>{glyph}</span>{label}</button>)}
      </nav>

      {mapExpanded && active && <div className="lx-modal-backdrop" onClick={() => setMapExpanded(false)}>
        <div className="lx-modal" onClick={e => e.stopPropagation()}>
          <button className="lx-modal-close" onClick={() => setMapExpanded(false)}>✕ CLOSE</button>
          <div className="lx-kicker">LAYER / {active.id.slice(0,8).toUpperCase()}</div>
          <h2>{active.title}</h2><p>{active.message}</p>
          <div className="lx-metadata"><span>LEFT BY {active.creator || "ANONYMOUS"}</span><span>{active.meters !== null ? formatDistance(active.meters) + " AWAY" : "ON DEVICE"}</span></div>
          <div className="lx-modal-actions"><button onClick={() => saveLayer(active.id)}>{savedIds.includes(active.id) ? "◆ SAVED" : "◇ SAVE"}</button><button onClick={() => share(active)}>↗ SHARE</button></div>
        </div>
      </div>}
    </main>
  );
}
