import { getAddress, isAddress, type Address } from 'viem'
import { createConfig, http } from 'wagmi'
import { anvil } from 'wagmi/chains'
import { injected, mock } from 'wagmi/connectors'

// Cuenta #0 de Anvil: la misma que despliega y recibe los 10.000 mUSDC.
export const ANVIL_ACCOUNT_0 = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'

// Cuenta del conector "sin wallet". Se cambia con VITE_ACCOUNT=0x... npm run dev.
// Tiene que estar desbloqueada en Anvil: las 10 cuentas por defecto ya lo están;
// cualquier otra se habilita con anvil_impersonateAccount.
const cuentaEnv = import.meta.env.VITE_ACCOUNT as string | undefined
if (cuentaEnv && !isAddress(cuentaEnv)) {
  throw new Error(`VITE_ACCOUNT no es una dirección válida: ${cuentaEnv}`)
}
export const LOCAL_ACCOUNT: Address = cuentaEnv ? getAddress(cuentaEnv) : ANVIL_ACCOUNT_0

export const config = createConfig({
  chains: [anvil],
  connectors: [
    mock({ accounts: [LOCAL_ACCOUNT], features: { reconnect: true } }),
    injected(),
  ],
  transports: {
    [anvil.id]: http('http://127.0.0.1:8545'),
  },
})

declare module 'wagmi' {
  interface Register {
    config: typeof config
  }
}
