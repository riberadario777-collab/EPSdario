import {useEffect,useState} from 'react'; import {useParams,Link} from 'react-router-dom'; import {supabase} from '../lib/supabase'
export default function ClientHistory(){
 const {id}=useParams(); const [c,setC]=useState<any>(null),[rows,setRows]=useState<any[]>([])
 useEffect(()=>{(async()=>{setC((await supabase.from('clients').select('*').eq('id',id).single()).data)
  const {data:o}=await supabase.from('orders').select('id,number,status,created_at,due_date,order_items(qty,dispatches(qty))').eq('client_id',id).order('number',{ascending:false})
  const {data:b}=await supabase.from('order_balance').select('order_id,total,paid').in('order_id',(o||[]).map((x:any)=>x.id))
  setRows((o||[]).map((x:any)=>({...x,b:(b||[]).find((y:any)=>y.order_id===x.id)})))})()},[id])
 const hoy=new Date().toISOString().slice(0,10)
 return <><div className="card"><Link to="/clientes">← Clientes</Link><h3>{c?.name}</h3><div>NIT/CI: {c?.nit_ci||'-'} · Tel: {c?.phone||'-'} · {c?.address||''}</div><p><b>Saldo pendiente total: Bs {rows.reduce((s,x)=>s+(x.b?Number(x.b.total)-Number(x.b.paid):0),0).toFixed(2)}</b></p></div>
 <div className="card tw"><table><thead><tr><th>Pedido</th><th>Fecha</th><th>Estado</th><th>Piezas ped./entreg.</th><th>Total</th><th>Pagado</th><th>Saldo</th><th>Vence</th></tr></thead><tbody>{rows.map(x=>{const q=x.order_items.reduce((s:number,i:any)=>s+i.qty,0),e=x.order_items.reduce((s:number,i:any)=>s+i.dispatches.reduce((a:number,d:any)=>a+d.qty,0),0),sal=x.b?x.b.total-x.b.paid:0
 return <tr key={x.id}><td>{x.number}</td><td>{x.created_at.slice(0,10)}</td><td>{x.status}</td><td>{q} / {e}</td><td>{x.b?Number(x.b.total).toFixed(2):'-'}</td><td>{x.b?Number(x.b.paid).toFixed(2):'-'}</td><td><b>{sal.toFixed(2)}</b></td><td style={x.due_date&&sal>0.005&&x.due_date<hoy?{color:'#b00020'}:{}}>{x.due_date||''}{x.due_date&&sal>0.005&&x.due_date<hoy&&' ⚠ vencido'}</td></tr>})}</tbody></table></div></>
}
