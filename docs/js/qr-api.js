(() => {
  const CREATE_ENDPOINT="https://api.qrserver.com/v1/create-qr-code/";
  const READ_ENDPOINT="https://api.qrserver.com/v1/read-qr-code/";

  const withTimeout = async (url, options={}, ms=15000) => {
    const controller=new AbortController();
    const timer=setTimeout(()=>controller.abort(),ms);
    try{
      return await fetch(url,{...options,signal:controller.signal,referrerPolicy:"no-referrer",cache:"no-store"});
    }finally{clearTimeout(timer);}
  };

  const classify = err => {
    if(err?.name === "AbortError") return {code:"Timeout", message:I18N.t("error.timeout")};
    if(err instanceof TypeError) return {code:"NetworkOrCORS", message:I18N.t("error.network")};
    return {code:"Unknown", message:err?.message || I18N.t("error.api")};
  };

  async function generate(payload,size,ecc){
    const body=new URLSearchParams({
      data:payload,
      size:`${size}x${size}`,
      ecc,
      format:"png",
      qzone:"4",
      "charset-source":"UTF-8",
      "charset-target":"UTF-8"
    });
    try{
      const res=await withTimeout(CREATE_ENDPOINT,{
        method:"POST",
        mode:"cors",
        headers:{"Content-Type":"application/x-www-form-urlencoded;charset=UTF-8"},
        body
      });
      if(!res.ok) throw Object.assign(new Error(I18N.t("error.http",{status:res.status})),{httpStatus:res.status});
      const blob=await res.blob();
      if(!blob.type.startsWith("image/")) throw new Error(I18N.t("error.api"));
      return blob;
    }catch(err){
      if(err.httpStatus) throw {code:`HTTP${err.httpStatus}`,message:err.message,technical:String(err)};
      const c=classify(err); throw {...c,technical:String(err)};
    }
  }

  async function read(blob){
    const form=new FormData();
    form.append("file",blob,"qr.png");
    form.append("outputformat","json");
    try{
      const res=await withTimeout(READ_ENDPOINT,{method:"POST",mode:"cors",body:form},15000);
      if(!res.ok) throw Object.assign(new Error(I18N.t("error.http",{status:res.status})),{httpStatus:res.status});
      const json=await res.json();
      const symbol=json?.[0]?.symbol?.[0];
      if(!symbol) return {ok:false,error:"Invalid reader response"};
      if(symbol.error) return {ok:false,error:String(symbol.error)};
      return {ok:true,data:String(symbol.data ?? "")};
    }catch(err){
      if(err.httpStatus) throw {code:`HTTP${err.httpStatus}`,message:err.message,technical:String(err)};
      const c=classify(err); throw {...c,technical:String(err)};
    }
  }

  function compare(expected,decoded){
    if(decoded === expected) return {kind:"exact"};
    const norm = s => s.replace(/\r\n/g,"\n").replace(/\r/g,"\n");
    if(norm(decoded) === norm(expected)) return {kind:"lineEndings"};
    if(norm(decoded).replace(/\n$/,"") === norm(expected).replace(/\n$/,"")) return {kind:"vcardFinalLineBreak"};
    try{
      if(typeof TextDecoder !== "undefined" && typeof TextEncoder !== "undefined"){
        const big5=new TextDecoder("big5",{fatal:false}).decode(new TextEncoder().encode(expected));
        if(big5 === decoded) return {kind:"charset"};
      }
    }catch(_){}
    const a=[...expected], b=[...decoded];
    let i=0; while(i<a.length && i<b.length && a[i]===b[i]) i++;
    return {kind:"mismatch", expectedLength:a.length, decodedLength:b.length, firstDifference:i};
  }

  window.QRApi={generate,read,compare,CREATE_ENDPOINT,READ_ENDPOINT};
})();
