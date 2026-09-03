(() => {
  const escVCard = value => String(value || "")
    .replaceAll("\\","\\\\").replaceAll("\r\n","\n").replaceAll("\r","\n")
    .replaceAll("\n","\\n").replaceAll(";","\\;").replaceAll(",","\\,");

  const escWifi = value => String(value || "")
    .replaceAll("\\","\\\\").replaceAll(";","\\;").replaceAll(",","\\,")
    .replaceAll(":","\\:").replaceAll('"','\\"');

  const clean = value => String(value || "").trim();

  window.Payloads = {
    hasUnicode(text){ return /[^\x00-\x7F]/u.test(text); },

    vcard(data){
      const first=clean(data.first), last=clean(data.last), company=clean(data.company);
      if(!first && !last && !company) throw new Error("required");
      const fn = clean(`${first} ${last}`) || company;
      const lines = ["BEGIN:VCARD","VERSION:3.0",`N:${escVCard(last)};${escVCard(first)};;;`,`FN:${escVCard(fn)}`];
      if(company) lines.push(`ORG:${escVCard(company)}`);
      if(clean(data.title)) lines.push(`TITLE:${escVCard(data.title)}`);
      if(clean(data.mobile)) lines.push(`TEL;TYPE=CELL:${escVCard(data.mobile)}`);
      if(clean(data.phone)) lines.push(`TEL;TYPE=VOICE:${escVCard(data.phone)}`);
      if(clean(data.email)) lines.push(`EMAIL:${escVCard(data.email)}`);
      if(clean(data.website)) lines.push(`URL:${escVCard(data.website)}`);
      const addressParts=[data.street,data.city,data.region,data.zip,data.country].map(clean);
      if(addressParts.some(Boolean)){
        lines.push(`ADR;TYPE=WORK:;;${escVCard(data.street)};${escVCard(data.city)};${escVCard(data.region)};${escVCard(data.zip)};${escVCard(data.country)}`);
      }
      if(clean(data.note)) lines.push(`NOTE:${escVCard(data.note)}`);
      lines.push("END:VCARD");
      return lines.join("\r\n");
    },

    url(data){
      const v=clean(data.url); if(!v) throw new Error("required"); return v;
    },

    wifi(data){
      const ssid=clean(data.ssid); if(!ssid) throw new Error("required");
      const enc=data.encryption || "WPA";
      const type=enc === "OPEN" ? "nopass" : enc;
      const pass=enc === "OPEN" ? "" : String(data.password || "");
      return `WIFI:T:${type};S:${escWifi(ssid)};P:${escWifi(pass)};H:${data.hidden ? "true":"false"};;`;
    },

    text(data){
      const v=String(data.text || ""); if(!v.trim()) throw new Error("required"); return v;
    },

    email(data){
      const to=clean(data.to); if(!to) throw new Error("required");
      const qs=new URLSearchParams();
      if(clean(data.subject)) qs.set("subject",data.subject);
      if(clean(data.body)) qs.set("body",data.body);
      const suffix=qs.toString();
      return `mailto:${to}${suffix ? "?" + suffix : ""}`;
    },

    phone(data){
      const v=clean(data.number); if(!v) throw new Error("required"); return `tel:${v}`;
    },

    sms(data){
      const v=clean(data.number); if(!v) throw new Error("required");
      return `SMSTO:${v}:${String(data.message || "")}`;
    },

    geo(data){
      const lat=Number(String(data.lat||"").replace(",","."));
      const lon=Number(String(data.lon||"").replace(",","."));
      if(!Number.isFinite(lat)||!Number.isFinite(lon)||lat < -90||lat > 90||lon < -180||lon > 180) throw new Error("required");
      return `geo:${lat},${lon}`;
    }
  };
})();
