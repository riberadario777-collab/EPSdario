import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
export default function Dispatch(){
 const [rows,setRows]=useState<any[]>([]),[q,setQ]=useState(''),[msg,setMsg]=useState('')
 const load=async()=>{const {data}=await supabase.from('order_items').select('id,qty,volume_piece,orders(number,created_at,clients(name)),products(code,espesor,largo,ancho),dispatches(qty)');setRows(data||[])}
 useEffect(()=>{load()},[])
 const list=rows.filter(r=>(`${r.orders?.number} ${r.orders?.clients?.name} ${r.products?.code}`).toLowerCase().includes(q.toLowerCase()))
 return <><div className="card"><input placeholder="Buscar pedido, cliente, material…" value={q} onChange={e=>setQ(e.target.value)}/><span className="err"> {msg}</span></div>
 <div className="card tw"><table><thead><tr><th>Ingreso</th><th>Pedido</th><th>Cliente</th><th>Material</th><th>Solic.</th><th>Entreg.</th><th>Saldo</th><th>m³</th><th>Estado</th><th/></tr></thead><tbody>{list.map(r=>{const e=r.dispatches.reduce((a:number,x:any)=>a+x.qty,0),s=r.qty-e
  return <tr key={r.id}><td>{r.orders?.created_at?.slice(0,10)}</td><td>{r.orders?.number}</td><td>{r.orders?.clients?.name}</td><td>{r.products?.code} {r.products?.espesor}x{r.products?.largo}x{r.products?.ancho}</td><td>{r.qty}</td><td>{e}</td><td>{s}</td><td>{(r.qty*r.volume_piece).toFixed(3)}</td><td>{s===0?'completado':e>0?'parcial':'pendiente'}</td>
  <td>{s>0&&<button className="b" onClick={async()=>{const n=Number(prompt('Piezas a entregar (saldo '+s+')'));if(!n)return;const {error}=await supabase.rpc('register_dispatch',{p_item:r.id,p_qty:n,p_key:crypto.randomUUID()});setMsg(error?error.message:'');load()}}>Entregar</button>}</td></tr>})}</tbody></table></div></>
}
