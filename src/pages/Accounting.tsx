import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
export default function Accounting(){
 const [ac,setAc]=useState<any[]>([]),[es,setEs]=useState<any[]>([]),[day,setDay]=useState(new Date().toISOString().slice(0,10)),[ds,setDs]=useState(''),[ls,setLs]=useState<any[]>([]),[a,setA]=useState(''),[d,setD]=useState(''),[c,setC]=useState(''),[msg,setMsg]=useState('')
 const load=async()=>{setAc((await supabase.from('account_balances').select('*')).data||[]);setEs((await supabase.from('journal_entries').select('*,journal_lines(debit,credit,accounts(code,name))').order('number',{ascending:false}).limit(30)).data||[])}
 useEffect(()=>{load()},[])
 const D=ls.reduce((s,x)=>s+x.debit,0),C=ls.reduce((s,x)=>s+x.credit,0),ok=D===C&&D>0
 return <><div className="card tw"><h3>Plan de cuentas y saldos</h3><table><thead><tr><th>Código</th><th>Cuenta</th><th>Tipo</th><th>Debe</th><th>Haber</th></tr></thead><tbody>{ac.map(x=><tr key={x.id}><td>{x.code}</td><td>{x.name}</td><td>{x.type}</td><td>{Number(x.debit).toFixed(2)}</td><td>{Number(x.credit).toFixed(2)}</td></tr>)}</tbody></table></div>
 <div className="card"><h3>Nuevo asiento</h3><input type="date" value={day} onChange={e=>setDay(e.target.value)}/><input placeholder="Descripción" value={ds} onChange={e=>setDs(e.target.value)}/><br/>
 <select value={a} onChange={e=>setA(e.target.value)}><option value="">Cuenta…</option>{ac.map(x=><option key={x.id} value={x.id}>{x.code} {x.name}</option>)}</select><input type="number" placeholder="Debe" value={d} onChange={e=>setD(e.target.value)}/><input type="number" placeholder="Haber" value={c} onChange={e=>setC(e.target.value)}/>
 <button className="b" onClick={()=>{if(a&&(Number(d)>0)!==(Number(c)>0)){setLs([...ls,{account:a,debit:Number(d)||0,credit:Number(c)||0}]);setD('');setC('')}}}>Agregar línea</button>
 {ls.map((x,i)=><div key={i}>{ac.find(y=>y.id===x.account)?.name}: debe {x.debit} · haber {x.credit}</div>)}<p>Debe {D.toFixed(2)} · Haber {C.toFixed(2)} {ok?'✔ cuadra':'✖ no cuadra'}</p>
 <button className="b" disabled={!ok||!ds} onClick={async()=>{const {error}=await supabase.rpc('post_entry',{p_day:day,p_desc:ds,p_ref:null,p_lines:ls});setMsg(error?error.message:'Asiento contabilizado');if(!error){setLs([]);setDs('');load()}}}>Contabilizar</button><span className="err"> {msg}</span></div>
 <div className="card tw"><h3>Últimos asientos (no se editan; se anulan con contra-asiento)</h3>{es.map(e=><div key={e.id}><b>#{e.number} {e.day}</b> {e.description} {e.ref&&`(${e.ref})`} {!e.ref&&<button className="b" onClick={async()=>{const {error}=await supabase.rpc('reverse_entry',{p_id:e.id});setMsg(error?error.message:'Anulado');load()}}>Anular</button>}
 <div style={{fontSize:13,marginLeft:12}}>{e.journal_lines.map((l:any,i:number)=><div key={i}>{l.accounts.code} {l.accounts.name} — D {l.debit} / H {l.credit}</div>)}</div></div>)}</div></>
}
