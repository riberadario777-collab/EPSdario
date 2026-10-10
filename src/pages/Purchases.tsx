import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
export default function Purchases(){
 const [su,setSu]=useState<any[]>([]),[pr,setPr]=useState<any[]>([]),[pu,setPu]=useState<any[]>([]),[ns,setNs]=useState(''),[s,setS]=useState(''),[doc,setDoc]=useState(''),[lines,setLines]=useState<any[]>([]),[p,setP]=useState(''),[q,setQ]=useState('1'),[c,setC]=useState(''),[err,setErr]=useState('')
 const load=async()=>{setSu((await supabase.from('suppliers').select('*').order('name')).data||[]);setPr((await supabase.from('products').select('id,code,espesor,largo,ancho,volume_piece,avg_cost_m3')).data||[]);setPu((await supabase.from('purchases').select('*,suppliers(name),purchase_items(qty,cost_m3,products(code))').order('created_at',{ascending:false})).data||[])}
 useEffect(()=>{load()},[])
 const addS=async()=>{const {error}=await supabase.from('suppliers').insert({name:ns});setErr(error?.message||'');setNs('');load()}
 const save=async()=>{if(!s||!lines.length)return setErr('Elija proveedor y productos')
  const {data:h,error}=await supabase.from('purchases').insert({supplier_id:s,doc}).select().single();if(error)return setErr(error.message)
  const {error:e2}=await supabase.from('purchase_items').insert(lines.map(x=>({purchase_id:h.id,product_id:x.p.id,qty:x.qty,cost_m3:x.c})));setErr(e2?.message||'');if(!e2){setLines([]);setDoc('');load()}}
 return <><div className="card"><h3>Proveedores</h3><input placeholder="Nuevo proveedor" value={ns} onChange={e=>setNs(e.target.value)}/><button className="b" onClick={addS}>Agregar</button></div>
 <div className="card"><h3>Nueva compra</h3><select value={s} onChange={e=>setS(e.target.value)}><option value="">Proveedor…</option>{su.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select><input placeholder="N° documento" value={doc} onChange={e=>setDoc(e.target.value)}/><br/>
 <select value={p} onChange={e=>setP(e.target.value)}><option value="">Producto…</option>{pr.map(x=><option key={x.id} value={x.id}>{x.code} {x.espesor}x{x.largo}x{x.ancho}</option>)}</select><input type="number" style={{width:70}} value={q} onChange={e=>setQ(e.target.value)}/><input type="number" placeholder="Costo Bs/m³" value={c} onChange={e=>setC(e.target.value)}/>
 <button className="b" onClick={()=>{const x=pr.find(y=>y.id===p);if(x&&c)setLines([...lines,{p:x,qty:Number(q),c:Number(c)}])}}>Agregar línea</button>
 {lines.map((x,i)=><div key={i}>{x.p.code} × {x.qty} · {(x.qty*x.p.volume_piece).toFixed(3)} m³ · Bs {(x.qty*x.p.volume_piece*x.c).toFixed(2)}</div>)}
 <button className="b" onClick={save}>Guardar compra</button><span className="err"> {err}</span></div>
 <div className="card tw"><table><thead><tr><th>N°</th><th>Proveedor</th><th>Doc</th><th>Líneas</th><th>Estado</th><th/></tr></thead><tbody>{pu.map(x=><tr key={x.id}><td>{x.number}</td><td>{x.suppliers?.name}</td><td>{x.doc}</td><td>{x.purchase_items.map((i:any)=>`${i.products.code}×${i.qty}`).join(', ')}</td><td>{x.status}</td>
 <td>{x.status==='borrador'&&<button className="b" onClick={async()=>{const {error}=await supabase.rpc('receive_purchase',{p_id:x.id});setErr(error?.message||'');load()}}>Recibir</button>}</td></tr>)}</tbody></table></div></>
}
