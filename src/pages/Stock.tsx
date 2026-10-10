import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
export default function Stock(){
 const [r,setR]=useState<any[]>([]),[m,setM]=useState('')
 const load=async()=>setR((await supabase.from('product_stock').select('*').order('code')).data||[])
 useEffect(()=>{load()},[])
 return <div className="card tw"><h3>Existencias (físico, reservado, disponible)</h3><span className="err">{m}</span><table><thead><tr><th>Producto</th><th>Físico</th><th>Reservado</th><th>Disponible</th><th>m³ físicos</th><th>Mínimo</th><th/></tr></thead><tbody>{r.map(x=><tr key={x.product_id} style={x.low?{background:'#fde8e8'}:{}}><td>{x.code} {x.espesor}x{x.largo}x{x.ancho}</td><td>{x.physical}</td><td>{x.reserved}</td><td><b>{x.available}</b></td><td>{Number(x.m3).toFixed(2)}</td><td>{x.min_stock}{x.low&&' ⚠ bajo'}</td>
 <td><button className="b" onClick={async()=>{const v=prompt('Stock mínimo (piezas)');if(v==null)return;const {error}=await supabase.from('products').update({min_stock:Number(v)}).eq('id',x.product_id);setM(error?error.message:'');load()}}>Mínimo</button></td></tr>)}</tbody></table></div>
}
