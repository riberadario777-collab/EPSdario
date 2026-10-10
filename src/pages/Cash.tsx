import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
const today=()=>new Date().toLocaleDateString('en-CA',{timeZone:'America/La_Paz'})
export default function Cash(){
 const [s,setS]=useState<any>(null),[exp,setExp]=useState<number|null>(null),[ex,setEx]=useState<any[]>([]),[op,setOp]=useState('0'),[cn,setCn]=useState(''),[c,setC]=useState(''),[a,setA]=useState(''),[m,setM]=useState('efectivo'),[key,setKey]=useState(crypto.randomUUID()),[msg,setMsg]=useState('')
 const load=async()=>{const {data}=await supabase.from('cash_sessions').select('*').eq('day',today()).maybeSingle();setS(data);if(data&&!data.closed)setExp((await supabase.rpc('cash_expected',{p_day:today()})).data);setEx((await supabase.from('expenses').select('*').order('created_at',{ascending:false}).limit(30)).data||[])}
 useEffect(()=>{load()},[])
 const run=async(p:any)=>{const {error}=await p;setMsg(error?error.message:'');load()}
 return <><div className="card"><h3>Caja del día {today()}</h3><span className="err">{msg}</span>
 {!s&&<div><input type="number" value={op} onChange={e=>setOp(e.target.value)}/><button className="b" onClick={()=>run(supabase.rpc('open_cash',{p_opening:Number(op)}))}>Abrir caja (Bs)</button></div>}
 {s&&!s.closed&&<div><p>Apertura: Bs {Number(s.opening).toFixed(2)} · <b>Saldo esperado en efectivo: Bs {exp==null?'…':Number(exp).toFixed(2)}</b></p><input type="number" placeholder="Efectivo contado" value={cn} onChange={e=>setCn(e.target.value)}/><button className="b" onClick={()=>confirm('¿Cerrar la caja? No se podrá reabrir.')&&run(supabase.rpc('close_cash',{p_counted:Number(cn)}))}>Cerrar caja</button></div>}
 {s?.closed&&<p>Caja cerrada. Esperado {Number(s.expected).toFixed(2)} · Contado {Number(s.counted).toFixed(2)} · <b>Diferencia {Number(s.difference).toFixed(2)}</b></p>}</div>
 <div className="card"><h3>Registrar gasto / egreso</h3><input placeholder="Concepto" value={c} onChange={e=>setC(e.target.value)}/><input type="number" placeholder="Monto Bs" value={a} onChange={e=>setA(e.target.value)}/><select value={m} onChange={e=>setM(e.target.value)}>{['efectivo','qr','transferencia','cheque'].map(x=><option key={x}>{x}</option>)}</select>
 <button className="b" disabled={!c||!Number(a)} onClick={async()=>{const {error}=await supabase.from('expenses').insert({concept:c,amount:Number(a),method:m,idem_key:key});setMsg(error?(error.code==='23505'?'Gasto ya registrado':error.message):'');if(!error){setC('');setA('');setKey(crypto.randomUUID());load()}}}>Guardar</button></div>
 <div className="card tw"><table><thead><tr><th>Fecha</th><th>Concepto</th><th>Medio</th><th>Bs</th></tr></thead><tbody>{ex.map(x=><tr key={x.id}><td>{x.created_at.slice(0,10)}</td><td>{x.concept}</td><td>{x.method}</td><td>{Number(x.amount).toFixed(2)}</td></tr>)}</tbody></table></div></>
}
