import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
export default function Commissions(){
 const [se,setSe]=useState<any[]>([]),[ors,setOrs]=useState<any[]>([]),[rows,setRows]=useState<any[]>([]),[ns,setNs]=useState(''),[s,setS]=useState(''),[o,setO]=useState(''),[k,setK]=useState('porcentaje'),[v,setV]=useState(''),[err,setErr]=useState('')
 const load=async()=>{setSe((await supabase.from('sellers').select('*').order('name')).data||[]);setOrs((await supabase.from('orders').select('id,number,clients(name)').order('number',{ascending:false})).data||[]);setRows((await supabase.from('commissions').select('*,sellers(name),orders(number)').order('created_at',{ascending:false})).data||[])}
 useEffect(()=>{load()},[])
 return <><div className="card"><h3>Vendedores externos</h3><input placeholder="Nombre" value={ns} onChange={e=>setNs(e.target.value)}/><button className="b" onClick={async()=>{const {error}=await supabase.from('sellers').insert({name:ns});setErr(error?.message||'');setNs('');load()}}>Agregar</button></div>
 <div className="card"><h3>Asignar comisión</h3><select value={s} onChange={e=>setS(e.target.value)}><option value="">Vendedor…</option>{se.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select>
 <select value={o} onChange={e=>setO(e.target.value)}><option value="">Pedido…</option>{ors.map(x=><option key={x.id} value={x.id}>#{x.number} {x.clients?.name}</option>)}</select>
 <select value={k} onChange={e=>setK(e.target.value)}><option value="porcentaje">% del total</option><option value="fijo">Monto fijo Bs</option></select><input type="number" value={v} onChange={e=>setV(e.target.value)}/>
 <button className="b" onClick={async()=>{const {error}=await supabase.from('commissions').insert({seller_id:s,order_id:o,kind:k,value:Number(v)});setErr(error?.message||'');load()}}>Asignar</button><span className="err"> {err}</span></div>
 <div className="card tw"><table><thead><tr><th>Pedido</th><th>Vendedor</th><th>Monto Bs</th><th>Estado</th><th/></tr></thead><tbody>{rows.map(r=><tr key={r.id}><td>{r.orders?.number}</td><td>{r.sellers?.name}</td><td>{Number(r.amount).toFixed(2)}</td><td>{r.paid_at?'pagada '+r.paid_at.slice(0,10):'pendiente'}</td>
 <td>{!r.paid_at&&<button className="b" onClick={async()=>{const {error}=await supabase.rpc('pay_commission',{p_id:r.id});setErr(error?.message||'');load()}}>Marcar pagada</button>}</td></tr>)}</tbody></table></div></>
}
