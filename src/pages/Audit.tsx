import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
export default function Audit(){
 const [r,setR]=useState<any[]>([]),[u,setU]=useState<any>({})
 useEffect(()=>{supabase.from('audit').select('*').order('at',{ascending:false}).limit(150).then(({data})=>setR(data||[]));supabase.from('profiles').select('id,full_name').then(({data})=>setU(Object.fromEntries((data||[]).map((x:any)=>[x.id,x.full_name]))))},[])
 return <div className="card tw"><h3>Auditoría (últimos 150 eventos)</h3><table><thead><tr><th>Fecha</th><th>Usuario</th><th>Acción</th><th>Detalle</th></tr></thead><tbody>{r.map(x=><tr key={x.id}><td>{x.at.slice(0,16).replace('T',' ')}</td><td>{u[x.who]||x.who}</td><td>{x.action}</td><td style={{fontSize:12}}>{JSON.stringify(x.detail)}</td></tr>)}</tbody></table></div>
}
