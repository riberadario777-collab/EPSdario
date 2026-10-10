import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
const BIZ={name:'PLASTOFORMO EPS',info:'Dirección / Teléfono del negocio'} // editar aquí
export default function Notes(){
 const [biz,setBiz]=useState(BIZ),[rows,setRows]=useState<any[]>([]),[note,setNote]=useState<any>(null),[msg,setMsg]=useState('')
 const load=async()=>setRows((await supabase.from('dispatches').select('id,qty,created_at,delivery_notes(number),order_items(qty,volume_piece,products(code,name,espesor,largo,ancho),orders(number,clients(name,nit_ci)),dispatches(qty,created_at))').order('created_at',{ascending:false})).data||[])
 useEffect(()=>{load();supabase.from('company_settings').select('*').single().then(({data})=>data&&setBiz(data as any))},[])
 const open=async(d:any)=>{let n=d.delivery_notes?.[0]?.number
  if(!n){const {data,error}=await supabase.from('delivery_notes').insert({dispatch_id:d.id}).select().single();if(error)return setMsg(error.message);n=data.number;load()}
  const it=d.order_items,entregado=it.dispatches.filter((x:any)=>x.created_at<=d.created_at).reduce((s:number,x:any)=>s+x.qty,0)
  setNote({n,d,it,saldo:it.qty-entregado})}
 return <><div className="card no-print"><h3>Notas de entrega</h3><span className="err">{msg}</span></div>
 {note&&<div className="card note"><h2>{biz.name}</h2><div>{biz.info}</div><h3>NOTA DE ENTREGA N° {String(note.n).padStart(6,'0')}</h3><p><i>Documento interno. No es una factura tributaria.</i></p>
  <p>Fecha: {note.d.created_at.slice(0,10)} · Pedido N° {note.it.orders.number}<br/>Cliente: {note.it.orders.clients.name} {note.it.orders.clients.nit_ci&&`· NIT/CI ${note.it.orders.clients.nit_ci}`}</p>
  <table><thead><tr><th>Código</th><th>Descripción</th><th>Medidas cm</th><th>Entregado</th><th>m³</th><th>Saldo</th></tr></thead><tbody><tr><td>{note.it.products.code}</td><td>{note.it.products.name}</td><td>{note.it.products.espesor}x{note.it.products.largo}x{note.it.products.ancho}</td><td>{note.d.qty}</td><td>{(note.d.qty*note.it.volume_piece).toFixed(3)}</td><td>{note.saldo}</td></tr></tbody></table>
  <p>Observaciones: ______________________________</p><br/><div style={{display:'flex',justifyContent:'space-between'}}><span>Entrega: ____________________<br/>Nombre y firma</span><span>Recibe: ____________________<br/>Nombre y firma</span></div>
  <button className="b no-print" onClick={()=>window.print()}>Imprimir</button></div>}
 <div className="card tw no-print"><table><thead><tr><th>Fecha</th><th>Pedido</th><th>Material</th><th>Piezas</th><th>Nota</th><th/></tr></thead><tbody>{rows.map(d=><tr key={d.id}><td>{d.created_at.slice(0,10)}</td><td>{d.order_items.orders.number}</td><td>{d.order_items.products.code}</td><td>{d.qty}</td><td>{d.delivery_notes?.[0]?.number||'—'}</td><td><button className="b" onClick={()=>open(d)}>{d.delivery_notes?.[0]?'Ver / imprimir':'Generar'}</button></td></tr>)}</tbody></table></div></>
}
