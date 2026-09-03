(() => {
  const $=sel=>document.querySelector(sel);
  const $$=sel=>[...document.querySelectorAll(sel)];
  const state={
    mode:"vcard",
    settings:{language:"auto",size:1000,ecc:"H",autoRead:true},
    payload:null,qrBlob:null,finalBlob:null,vcfBlob:null,logoImage:null,
    formData:{},
    debug:[]
  };

  const modes={
    vcard:{title:"mode.vcard.title",subtitle:"mode.vcard.subtitle"},
    url:{title:"mode.url.title",subtitle:"mode.url.subtitle"},
    wifi:{title:"mode.wifi.title",subtitle:"mode.wifi.subtitle"},
    text:{title:"mode.text.title",subtitle:"mode.text.subtitle"},
    email:{title:"mode.email.title",subtitle:"mode.email.subtitle"},
    phone:{title:"mode.phone.title",subtitle:"mode.phone.subtitle"},
    sms:{title:"mode.sms.title",subtitle:"mode.sms.subtitle"},
    geo:{title:"mode.geo.title",subtitle:"mode.geo.subtitle"}
  };

  function log(event,details){
    const line=`[${new Date().toLocaleTimeString()}] ${event}: ${details}`;
    state.debug.push(line); if(state.debug.length>50) state.debug.shift();
    console.info(line);
  }

  function loadSettings(){
    try{
      const raw=localStorage.getItem("qrweb.settings");
      if(raw) Object.assign(state.settings,JSON.parse(raw));
    }catch(_){}
    state.settings.language=localStorage.getItem("qrweb.language") || state.settings.language || "auto";
  }
  function saveSettings(){
    localStorage.setItem("qrweb.settings",JSON.stringify(state.settings));
    localStorage.setItem("qrweb.language",state.settings.language);
  }
  function resolveLang(){
    if(state.settings.language==="de"||state.settings.language==="en") return state.settings.language;
    return (navigator.language||"en").toLowerCase().startsWith("de")?"de":"en";
  }
  function captureFormData(){
    const data={};
    $$("[data-field]").forEach(el=>{
      data[el.dataset.field]=el.type==="checkbox"?el.checked:el.value;
    });
    state.formData[state.mode]=data;
    return data;
  }

  function restoreFormData(data){
    if(!data) return;
    $$("[data-field]").forEach(el=>{
      if(!Object.prototype.hasOwnProperty.call(data,el.dataset.field)) return;
      if(el.type==="checkbox") el.checked=Boolean(data[el.dataset.field]);
      else el.value=data[el.dataset.field] ?? "";
    });
  }

  function applyLanguage(){
    const preserved=captureFormData();
    I18N.set(resolveLang());
    renderModeHeader();
    renderForm(preserved);
    updateSummary();
  }
  function setStatus(key,type="ok"){
    $("#statusText").textContent=I18N.t(key);
    $("#statusDot").className=`status-dot ${type}`;
  }

  function field(name,label,type="text",opts={}){
    const full=opts.full?" full":"";
    const attrs=[
      `id="${name}"`,`data-field="${name}"`,`class="input"`,`type="${type}"`,
      opts.placeholder?`placeholder="${escapeAttr(opts.placeholder)}"`:"",
      opts.maxlength?`maxlength="${opts.maxlength}"`:"",
      opts.inputmode?`inputmode="${opts.inputmode}"`:""
    ].filter(Boolean).join(" ");
    return `<div class="field${full}"><label for="${name}">${escapeHtml(label)}</label><input ${attrs}></div>`;
  }
  function textarea(name,label,opts={}){
    return `<div class="field${opts.full?" full":""}"><label for="${name}">${escapeHtml(label)}</label><textarea id="${name}" data-field="${name}" maxlength="${opts.maxlength||2048}"></textarea></div>`;
  }
  function escapeHtml(v){return String(v).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));}
  function escapeAttr(v){return escapeHtml(v);}

  function renderModeHeader(){
    $("#modeTitle").textContent=I18N.t(modes[state.mode].title);
    $("#modeSubtitle").textContent=I18N.t(modes[state.mode].subtitle);
    $$(".nav-btn").forEach(b=>b.classList.toggle("active",b.dataset.mode===state.mode));
  }

  function renderForm(preserved=null){
    const t=I18N.t.bind(I18N);
    let html="";
    if(state.mode==="vcard"){
      html=`<section class="form-section"><div class="section-heading">${t("vcard.contact")}</div><div class="form-grid">
        ${field("first",t("vcard.first"))}${field("last",t("vcard.last"))}
        ${field("company",t("vcard.company"))}${field("title",t("vcard.title"))}
        ${field("mobile",t("vcard.mobile"),"tel")}${field("phone",t("vcard.phone"),"tel")}
        ${field("email",t("vcard.email"),"email")}${field("website",t("vcard.website"),"url")}
      </div></section>
      <section class="form-section"><div class="section-heading">${t("vcard.address")}</div><div class="form-grid">
        ${field("street",t("vcard.street"),"text",{full:true})}
        ${field("zip",t("vcard.zip"))}${field("city",t("vcard.city"))}
        ${field("region",t("vcard.region"))}${field("country",t("vcard.country"))}
        ${textarea("note",t("vcard.note"),{full:true,maxlength:1024})}
      </div></section>`;
    }else if(state.mode==="url"){
      html=`<section class="form-section"><div class="form-grid one">${field("url",t("url.target"),"url",{full:true})}</div></section>`;
    }else if(state.mode==="wifi"){
      html=`<section class="form-section"><div class="form-grid">
        ${field("ssid",t("wifi.ssid"),"text",{full:true,maxlength:128})}
        ${field("password",t("wifi.password"),"password",{full:true,maxlength:256})}
        <div class="field"><label for="encryption">${t("wifi.encryption")}</label><select id="encryption" data-field="encryption">
          <option value="WPA">${t("wifi.wpa")}</option><option value="WEP">${t("wifi.wep")}</option><option value="OPEN">${t("wifi.open")}</option>
        </select></div>
        <div class="field"><label>&nbsp;</label><label class="check-row"><input id="hidden" data-field="hidden" type="checkbox"> ${t("wifi.hidden")}</label></div>
      </div></section><div class="notice">${t("wifi.notice")}</div>`;
    }else if(state.mode==="text"){
      html=`<section class="form-section">${textarea("text",t("text.value"),{full:true,maxlength:4096})}</section>`;
    }else if(state.mode==="email"){
      html=`<section class="form-section"><div class="form-grid">
        ${field("to",t("email.to"),"email",{full:true})}${field("subject",t("email.subject"),"text",{full:true,maxlength:256})}
        ${textarea("body",t("email.body"),{full:true,maxlength:2048})}
      </div></section>`;
    }else if(state.mode==="phone"){
      html=`<section class="form-section"><div class="form-grid one">${field("number",t("phone.number"),"tel",{full:true})}</div></section>`;
    }else if(state.mode==="sms"){
      html=`<section class="form-section"><div class="form-grid one">${field("number",t("sms.number"),"tel",{full:true})}${textarea("message",t("sms.message"),{full:true,maxlength:1024})}</div></section>`;
    }else if(state.mode==="geo"){
      html=`<section class="form-section"><div class="form-grid">${field("lat",t("geo.lat"),"text",{inputmode:"decimal"})}${field("lon",t("geo.lon"),"text",{inputmode:"decimal"})}</div></section>`;
    }
    $("#formHost").innerHTML=html;
    const cached=preserved || state.formData[state.mode] || null;
    restoreFormData(cached);
    if(state.mode==="vcard" && !cached?.country){
      $("#country").value=I18N.current==="de"?"Deutschland":"Germany";
    }
  }

  function collect(){
    const data={};
    $$("[data-field]").forEach(el=>{
      data[el.dataset.field]=el.type==="checkbox"?el.checked:el.value;
    });
    state.formData[state.mode]=data;
    return data;
  }

  function buildPayload(){
    try{return Payloads[state.mode](collect());}
    catch(err){if(err.message==="required") throw new Error(I18N.t("error.required")); throw err;}
  }

  async function showModal({title,html,buttons=[{label:I18N.t("common.close"),value:true,className:"secondary"}]}){
    return new Promise(resolve=>{
      $("#modalTitle").textContent=title;
      $("#modalBody").innerHTML=html;
      const actions=$("#modalActions"); actions.textContent="";
      const finish=value=>{$("#modalBackdrop").classList.add("hidden");$("#modalBackdrop").setAttribute("aria-hidden","true");resolve(value);};
      for(const b of buttons){
        const btn=document.createElement("button");btn.type="button";btn.className=`btn ${b.className||"secondary"}`;btn.textContent=b.label;btn.addEventListener("click",()=>finish(b.value));actions.appendChild(btn);
      }
      $("#modalClose").onclick=()=>finish(false);
      $("#modalBackdrop").classList.remove("hidden");$("#modalBackdrop").setAttribute("aria-hidden","false");
    });
  }

  async function unicodeGuard(payload){
    if(!Payloads.hasUnicode(payload)) return true;
    log("Unicode guard",`Non-ASCII payload detected; length=${payload.length}; payload text not logged`);
    return await showModal({
      title:I18N.t("unicode.title"),
      html:`<p>${escapeHtml(I18N.t("unicode.body"))}</p>`,
      buttons:[
        {label:I18N.t("common.cancel"),value:false,className:"secondary"},
        {label:I18N.t("common.continue"),value:true,className:"primary"}
      ]
    });
  }

  async function blobToImage(blob){
    const url=URL.createObjectURL(blob);
    try{
      const img=new Image();
      await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;img.src=url;});
      return img;
    }finally{setTimeout(()=>URL.revokeObjectURL(url),1000);}
  }

  async function loadLogo(file){
    if(!file){state.logoImage=null;$("#logoName").textContent=I18N.t("logo.none");return;}
    if(!/^image\/(png|jpeg|bmp)$/i.test(file.type)) throw new Error(I18N.t("error.logo"));
    const url=URL.createObjectURL(file);
    try{
      const img=new Image();
      await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;img.src=url;});
      state.logoImage=img;$("#logoName").textContent=file.name;
    }finally{setTimeout(()=>URL.revokeObjectURL(url),1000);}
  }

  async function compose(qrBlob){
    const canvas=$("#qrCanvas"),ctx=canvas.getContext("2d",{alpha:false});
    canvas.width=state.settings.size;canvas.height=state.settings.size;
    ctx.fillStyle="#fff";ctx.fillRect(0,0,canvas.width,canvas.height);
    const img=await blobToImage(qrBlob);
    ctx.drawImage(img,0,0,canvas.width,canvas.height);
    if($("#useLogo").checked && state.logoImage){
      setStatus("status.logo","busy");
      const pct=Number($("#logoSize").value)/100;
      const box=Math.round(canvas.width*pct);
      const pad=Math.max(8,Math.round(box*.14));
      const cx=canvas.width/2,cy=canvas.height/2;
      ctx.fillStyle="#fff";
      roundRect(ctx,cx-box/2-pad,cy-box/2-pad,box+pad*2,box+pad*2,Math.round(pad*.8));
      ctx.fill();
      const scale=Math.min(box/state.logoImage.width,box/state.logoImage.height);
      const w=state.logoImage.width*scale,h=state.logoImage.height*scale;
      ctx.drawImage(state.logoImage,cx-w/2,cy-h/2,w,h);
    }
    $("#previewPlaceholder").classList.add("hidden");canvas.classList.add("visible");
    return await new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error("Canvas export failed")),"image/png"));
  }
  function roundRect(ctx,x,y,w,h,r){
    r=Math.min(r,w/2,h/2);ctx.beginPath();ctx.moveTo(x+r,y);ctx.arcTo(x+w,y,x+w,y+h,r);ctx.arcTo(x+w,y+h,x,y+h,r);ctx.arcTo(x,y+h,x,y,r);ctx.arcTo(x,y,x+w,y,r);ctx.closePath();
  }

  function filename(){
    const data=collect();
    const safe=v=>String(v||"").trim().replace(/[<>:"/\\|?*\u0000-\u001F]/g,"_").replace(/\s+/g,"_").slice(0,80);
    if(state.mode==="vcard") return `${safe(`${data.first||""}_${data.last||""}`)||safe(data.company)||"Kontakt"}_Kontakt`;
    if(state.mode==="wifi") return `${safe(data.ssid)||"WLAN"}_WLAN`;
    return I18N.t(`filename.${state.mode}`);
  }

  function enableResults(){
    $("#btnDownload").disabled=!state.finalBlob;
    $("#btnVerify").disabled=!state.finalBlob || !state.payload;
    $("#btnVcf").disabled=!(state.mode==="vcard" && state.vcfBlob);
  }
  function invalidateResult(){
    state.payload=state.qrBlob=state.finalBlob=state.vcfBlob=null;
    $("#qrCanvas").classList.remove("visible");$("#previewPlaceholder").classList.remove("hidden");
    enableResults();
  }

  function hasResult(){
    return Boolean(state.payload || state.qrBlob || state.finalBlob || state.vcfBlob);
  }

  function invalidateResultIfPresent(reason){
    if(!hasResult()) return;
    invalidateResult();
    setStatus("status.changed","warn");
    log("Result invalidated",`${reason}; previous QR is no longer treated as current; payload text not logged`);
  }

  async function generate(){
    invalidateResult();
    setStatus("status.preparing","busy");
    let payload;
    try{payload=buildPayload();}
    catch(err){setStatus("status.error","error");await errorDialog(err.message);return;}
    const go=await unicodeGuard(payload); if(!go){setStatus("status.ready","ok");return;}
    try{
      state.payload=payload;
      setStatus("status.generating","busy");
      log("Generate",`Mode=${state.mode}; Size=${state.settings.size}; ECC=${state.settings.ecc}; Logo=${$("#useLogo").checked}; PayloadLength=${payload.length}; payload text not logged`);
      state.qrBlob=await QRApi.generate(payload,state.settings.size,$("#useLogo").checked?"H":state.settings.ecc);
      state.finalBlob=await compose(state.qrBlob);
      if(state.mode==="vcard") state.vcfBlob=new Blob([payload],{type:"text/vcard;charset=utf-8"});
      enableResults();
      if(state.settings.autoRead) await verify(true);
      else setStatus("status.success","ok");
    }catch(err){
      state.payload=state.qrBlob=state.finalBlob=state.vcfBlob=null;enableResults();setStatus("status.error","error");
      log("Generate FAILED",`${err.code||"Unknown"} | ${err.message||err}; payload text not logged`);
      await errorDialog(err.message||I18N.t("error.api"),err);
    }
  }

  async function verify(automatic=false){
    if(!state.finalBlob||!state.payload) return;
    setStatus("status.testing","busy");
    log(automatic?"Read test":"Manual read test","Starting online verification via QRServer");
    try{
      const result=await QRApi.read(state.finalBlob);
      if(!result.ok){
        setStatus("status.testUnavailable","warn");
        log("Read test",`DECODE FAILED | ${result.error}`);
        if(!automatic) await showModal({title:I18N.t("verify.title"),html:`<p>${escapeHtml(I18N.t("verify.failed"))}</p><div class="debug-box">${escapeHtml(result.error)}</div>`});
        return;
      }
      const cmp=QRApi.compare(state.payload,result.data);
      if(cmp.kind==="exact"||cmp.kind==="lineEndings"||cmp.kind==="vcardFinalLineBreak"){
        setStatus("status.verified","ok");log("Read test",`PASS [${cmp.kind}]`);
        if(!automatic) await showModal({title:I18N.t("verify.title"),html:`<p>${escapeHtml(I18N.t("verify.exact"))}</p>`});
      }else if(cmp.kind==="charset"){
        setStatus("status.warnCharset","warn");log("Read test","WARNING [CharsetAmbiguity] | payload text not logged");
        if(!automatic) await showModal({title:I18N.t("verify.title"),html:`<p>${escapeHtml(I18N.t("verify.charset"))}</p>`});
      }else{
        setStatus("status.warnCharset","warn");
        log("Read test",`MISMATCH | ExpectedChars=${cmp.expectedLength}; DecodedChars=${cmp.decodedLength}; FirstDifferenceIndex=${cmp.firstDifference}; payload text not logged`);
        if(!automatic) await showModal({title:I18N.t("verify.title"),html:`<p>${escapeHtml(I18N.t("verify.mismatch"))}</p>`});
      }
    }catch(err){
      setStatus("status.testUnavailable","warn");log("Read test",`UNAVAILABLE [${err.code||"Unknown"}] | ${err.message}`);
      if(!automatic) await errorDialog(err.message||I18N.t("error.read"),err);
    }
  }

  async function errorDialog(message,err=null){
    const technical=err?.technical?`<div class="debug-box">${escapeHtml(err.technical)}</div>`:"";
    await showModal({title:I18N.t("status.error"),html:`<p>${escapeHtml(message)}</p>${technical}`});
  }

  function downloadBlob(blob,name){
    const url=URL.createObjectURL(blob);const a=document.createElement("a");a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }

  function updateSummary(){
    $("#summarySize").textContent=`${state.settings.size} px`;
    $("#summaryEcc").textContent=state.settings.ecc;
    $("#summaryRead").textContent=I18N.t(state.settings.autoRead?"common.on":"common.off");
    $("#footerSize").textContent=`${state.settings.size} px`;
    $("#footerEcc").textContent=`ECC ${state.settings.ecc}`;
  }

  async function settingsDialog(){
    const cur=state.settings;
    const html=`<div class="settings-stack">
      <div class="settings-group"><h3>${escapeHtml(I18N.t("settings.language"))}</h3>
        <select id="setLang"><option value="auto">${I18N.t("settings.auto")}</option><option value="de">${I18N.t("settings.de")}</option><option value="en">${I18N.t("settings.en")}</option></select>
      </div>
      <div class="settings-group"><h3>QR-Code</h3><div class="form-grid">
        <div class="field"><label>${I18N.t("settings.size")}</label><select id="setSize">${[400,600,800,900,1000].map(v=>`<option value="${v}">${v} px</option>`).join("")}</select></div>
        <div class="field"><label>${I18N.t("settings.ecc")}</label><select id="setEcc">${["L","M","Q","H"].map(v=>`<option value="${v}">${v}</option>`).join("")}</select></div>
        <div class="field full"><label class="check-row"><input id="setAutoRead" type="checkbox"> ${I18N.t("settings.autoread")}</label></div>
      </div></div>
      <div class="notice">${escapeHtml(I18N.t("settings.note"))}</div>
    </div>`;
    const promise=showModal({title:I18N.t("settings.title"),html,buttons:[
      {label:I18N.t("common.cancel"),value:false,className:"secondary"},
      {label:I18N.t("common.save"),value:true,className:"primary"}
    ]});
    $("#setLang").value=cur.language;$("#setSize").value=String(cur.size);$("#setEcc").value=cur.ecc;$("#setAutoRead").checked=cur.autoRead;
    const ok=await promise;if(!ok)return;
    const before={...cur};
    const preserved=captureFormData();
    cur.language=$("#setLang").value;
    cur.size=Number($("#setSize").value);
    cur.ecc=$("#setEcc").value;
    cur.autoRead=$("#setAutoRead").checked;
    saveSettings();
    I18N.set(resolveLang());
    renderModeHeader();
    renderForm(preserved);
    updateSummary();
    if(before.size!==cur.size || before.ecc!==cur.ecc){
      invalidateResultIfPresent("QR size or ECC setting changed");
    }else{
      setStatus("status.ready","ok");
    }
  }

  async function infoDialog(){
    await showModal({title:I18N.t("info.title"),html:`<p>${escapeHtml(I18N.t("info.body"))}</p>
      <div class="notice"><strong>Privacy:</strong> ${escapeHtml(I18N.t("privacy.onlineShort"))}</div>
      <p class="muted small">Create API: <code>${QRApi.CREATE_ENDPOINT}</code><br>Read API: <code>${QRApi.READ_ENDPOINT}</code></p>`});
  }

  function bind(){
    $$(".nav-btn").forEach(btn=>btn.addEventListener("click",()=>{
      captureFormData();
      state.mode=btn.dataset.mode;
      invalidateResult();
      renderModeHeader();
      renderForm();
      setStatus("status.ready","ok");
    }));
    $("#btnNew").addEventListener("click",()=>{
      state.formData[state.mode]={};
      invalidateResult();
      renderForm({});
      setStatus("status.ready","ok");
    });
    $("#btnSettings").addEventListener("click",settingsDialog);$("#btnSettings2").addEventListener("click",settingsDialog);$("#btnInfo").addEventListener("click",infoDialog);
    $("#btnGenerate").addEventListener("click",generate);
    $("#btnDownload").addEventListener("click",()=>state.finalBlob&&downloadBlob(state.finalBlob,`${filename()}.png`));
    $("#btnVcf").addEventListener("click",()=>state.vcfBlob&&downloadBlob(state.vcfBlob,`${filename()}.vcf`));
    $("#btnVerify").addEventListener("click",()=>verify(false));

    $("#formHost").addEventListener("input",()=>{
      captureFormData();
      invalidateResultIfPresent("QR input changed");
    });
    $("#formHost").addEventListener("change",()=>{
      captureFormData();
      invalidateResultIfPresent("QR input changed");
    });

    $("#useLogo").addEventListener("change",e=>{
      $("#logoControls").classList.toggle("hidden",!e.target.checked);
      invalidateResultIfPresent("Logo usage changed");
    });
    $("#logoFile").addEventListener("change",async e=>{
      try{
        await loadLogo(e.target.files?.[0]);
        invalidateResultIfPresent("Logo file changed");
      }catch(err){await errorDialog(err.message);}
    });
    $("#logoSize").addEventListener("input",e=>{
      $("#logoSizeValue").textContent=`${e.target.value} %`;
      invalidateResultIfPresent("Logo size changed");
    });
    document.addEventListener("keydown",e=>{if(e.key==="Escape"&&!$("#modalBackdrop").classList.contains("hidden")) $("#modalClose").click();});
  }

  function init(){
    loadSettings();I18N.current=resolveLang();I18N.set(I18N.current);bind();renderModeHeader();renderForm();updateSummary();setStatus("status.ready","ok");
    log("Application","GitHub Pages web version initialized; fixed provider=QRServer; payload contents are not logged");
  }
  document.addEventListener("DOMContentLoaded",init);
})();
