import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
export default function Payments(){
 const [rows,setRows]=useState<any[]>([]),[o,setO]=useState(''),[a,setA]=useState(''),[m,setM]=useState('efectivo'),[key,setKey]=useState(crypto.randomUUID()),[msg,setMsg]=useState('')
 const load=async()=>setRows((await supabase.from('order_balance').select('*').order('number',{ascending:false})).data||[])
 useEffect(()=>{load()},[])
 const pay=async()=>{const {error}=await supabase.from('payments').insert({order_id:o,amount:Number(a),method:m,idem_key:key});setMsg(error?(error.code==='23505'?'Pago ya registrado':error.message):'Pago registrado');if(!error){setA('');setKey(crypto.randomUUID());load()}}
 const sel=rows.find(r=>r.order_id===o)
 return <><div className="card"><h3>Registrar cobro</h3><select value={o} onChange={e=>setO(e.target.value)}><option value="">Pedido…</option>{rows.map(r=><option key={r.order_id} value={r.order_id}>#{r.number} {r.client} · saldo {(r.total-r.paid).toFixed(2)}</option>)}</select>
 <input type="number" placeholder={sel?`Máx ${(sel.total-sel.paid).toFixed(2)}`:'Monto Bs'} value={a} onChange={e=>setA(e.target.value)}/>
 <select value={m} onChange={e=>setM(e.target.value)}>{['efectivo','qr','transferencia','cheque'].map(x=><option key={x}>{x}</option>)}</select>
 <button className="b" disabled={!o||!Number(a)||(sel&&Number(a)>sel.total-sel.paid+0.005)} onClick={pay}>Cobrar</button> <span className="err">{msg}</span></div>
 <div className="card tw"><table><thead><tr><th>N°</th><th>Cliente</th><th>Total</th><th>Pagado</th><th>Saldo</th><th>Vence</th></tr></thead><tbody>{rows.map(r=><tr key={r.order_id}><td>{r.number}</td><td>{r.client}</td><td>{Number(r.total).toFixed(2)}</td><td>{Number(r.paid).toFixed(2)}</td><td><b>{(r.total-r.paid).toFixed(2)}</b></td><td style={r.due_date&&r.total-r.paid>0.005&&r.due_date<new Date().toISOString().slice(0,10)?{color:'#b00020'}:{}}>{r.due_date||''}{r.due_date&&r.total-r.paid>0.005&&r.due_date<new Date().toISOString().slice(0,10)&&' ⚠ vencido'}</td></tr>)}</tbody></table></div></>
}
