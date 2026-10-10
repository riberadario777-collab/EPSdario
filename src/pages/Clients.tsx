import {Link} from 'react-router-dom'; import Crud from '../components/Crud'
export default ()=><Crud table="clients" title="Clientes" fields={[{k:'name',l:'Nombre / Razón social'},{k:'nit_ci',l:'NIT/CI'},{k:'phone',l:'Teléfono'},{k:'email',l:'Correo'},{k:'address',l:'Dirección'}]} cols={['name','nit_ci','phone','address']} actions={r=><Link to={'/cliente/'+r.id}>Historial</Link>}/>
