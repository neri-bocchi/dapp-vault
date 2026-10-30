import { useState } from 'react'
import { formatUnits, parseUnits, type Address } from 'viem'
import {
  useConfig,
  useConnect,
  useConnection,
  useConnectors,
  useDisconnect,
  useReadContract,
  useReadContracts,
  useWriteContract,
} from 'wagmi'
import { waitForTransactionReceipt } from 'wagmi/actions'
import { anvil } from 'wagmi/chains'
import { usdc, vault } from './contracts.ts'
import { LOCAL_ACCOUNT } from './wagmi.ts'

// Valores esperados; igual se leen on-chain. Las shares tienen 6 + offset 6 = 12 decimales.
const USDC_DECIMALS_DEFAULT = 6
const SHARE_DECIMALS_DEFAULT = 12

function parseMonto(texto: string, decimales: number): bigint | undefined {
  try {
    const valor = parseUnits(texto.trim(), decimales)
    return valor > 0n ? valor : undefined
  } catch {
    return undefined
  }
}

function fmt(valor: bigint | undefined, decimales: number, maxDecimales = 6): string {
  if (valor === undefined) return '—'
  const [entero, frac = ''] = formatUnits(valor, decimales).split('.')
  const recortado = frac.slice(0, maxDecimales).replace(/0+$/, '')
  return Number(entero).toLocaleString('es-AR') + (recortado ? `,${recortado}` : '')
}

export default function App() {
  const { address, chainId, isConnected } = useConnection()
  const connectors = useConnectors()
  const connect = useConnect()
  const disconnect = useDisconnect()

  if (!isConnected || !address) {
    return (
      <main>
        <h1>SimpleVault</h1>
        <p>Conectá una cuenta en Anvil (chainId {anvil.id}).</p>
        <div className="fila">
          {connectors.map((c) => (
            <button key={c.uid} onClick={() => connect.mutate({ connector: c })} disabled={connect.isPending}>
              {c.type === 'mock' ? `Cuenta local ${LOCAL_ACCOUNT.slice(0, 6)}…${LOCAL_ACCOUNT.slice(-4)}` : c.name}
            </button>
          ))}
        </div>
        {connect.error && <p className="error">{connect.error.message}</p>}
      </main>
    )
  }

  return (
    <main>
      <header className="fila">
        <h1>SimpleVault</h1>
        <button className="secundario" onClick={() => disconnect.mutate()}>
          Desconectar
        </button>
      </header>
      <p className="cuenta">{address}</p>
      {chainId !== anvil.id ? (
        <p className="error">Cambiá la wallet a Anvil (chainId {anvil.id}).</p>
      ) : (
        <Vault cuenta={address} />
      )}
    </main>
  )
}

function Vault({ cuenta }: { cuenta: Address }) {
  const config = useConfig()
  const [monto, setMonto] = useState('')
  const [estado, setEstado] = useState<string>()
  const [error, setError] = useState<string>()
  const write = useWriteContract()

  const lecturas = useReadContracts({
    contracts: [
      { ...usdc, functionName: 'decimals' },
      { ...usdc, functionName: 'symbol' },
      { ...usdc, functionName: 'balanceOf', args: [cuenta] },
      { ...usdc, functionName: 'allowance', args: [cuenta, vault.address] },
      { ...vault, functionName: 'decimals' },
      { ...vault, functionName: 'symbol' },
      { ...vault, functionName: 'balanceOf', args: [cuenta] },
      { ...vault, functionName: 'totalAssets' },
    ],
    query: { refetchInterval: 4000 },
  })
  const [usdcDec, usdcSym, usdcBal, allowance, shareDec, shareSym, shareBal, totalAssets] =
    lecturas.data?.map((r) => r.result) ?? []

  const dU = (usdcDec as number | undefined) ?? USDC_DECIMALS_DEFAULT
  const dS = (shareDec as number | undefined) ?? SHARE_DECIMALS_DEFAULT
  const symU = (usdcSym as string | undefined) ?? 'mUSDC'
  const symS = (shareSym as string | undefined) ?? 'svUSDC'
  const balU = usdcBal as bigint | undefined
  const balS = shareBal as bigint | undefined
  const allow = (allowance as bigint | undefined) ?? 0n

  // 1 share = 10 ** 12 unidades, no 10 ** 6.
  const unaShare = useReadContract({
    ...vault,
    functionName: 'convertToAssets',
    args: [10n ** BigInt(dS)],
    query: { refetchInterval: 4000 },
  })

  const assets = parseMonto(monto, dU)
  const preview = useReadContract({
    ...vault,
    functionName: 'previewDeposit',
    args: [assets ?? 0n],
    query: { enabled: assets !== undefined, refetchInterval: 4000 },
  })

  const previewRedeem = useReadContract({
    ...vault,
    functionName: 'previewRedeem',
    args: [balS ?? 0n],
    query: { enabled: !!balS, refetchInterval: 4000 },
  })

  const ocupado = write.isPending || estado !== undefined
  const saldoInsuficiente = assets !== undefined && balU !== undefined && assets > balU
  const necesitaApprove = assets !== undefined && allow < assets

  async function enviar(etiqueta: string, tx: Parameters<typeof write.mutateAsync>[0]) {
    setError(undefined)
    try {
      setEstado(`${etiqueta}: firmando…`)
      const hash = await write.mutateAsync(tx)
      setEstado(`${etiqueta}: esperando confirmación…`)
      const recibo = await waitForTransactionReceipt(config, { hash })
      if (recibo.status !== 'success') throw new Error(`${etiqueta} revirtió`)
      return true
    } catch (e) {
      setError(e instanceof Error ? e.message.split('\n')[0] : String(e))
      return false
    } finally {
      setEstado(undefined)
      await Promise.all([lecturas.refetch(), unaShare.refetch(), previewRedeem.refetch()])
    }
  }

  async function approve() {
    if (!assets) return
    await enviar('Approve', { ...usdc, functionName: 'approve', args: [vault.address, assets] })
  }

  async function deposit() {
    if (!assets) return
    const ok = await enviar('Deposit', { ...vault, functionName: 'deposit', args: [assets, cuenta] })
    if (ok) setMonto('')
  }

  async function redeem() {
    if (!balS) return
    await enviar('Redeem', { ...vault, functionName: 'redeem', args: [balS, cuenta, cuenta] })
  }

  return (
    <>
      <section className="tarjetas">
        <div className="tarjeta">
          <span>Balance {symU}</span>
          <strong>{fmt(balU, dU)}</strong>
        </div>
        <div className="tarjeta">
          <span>Balance {symS}</span>
          <strong>{fmt(balS, dS)}</strong>
          <small>≈ {fmt(previewRedeem.data, dU)} {symU}</small>
        </div>
        <div className="tarjeta">
          <span>1 {symS} vale</span>
          <strong>{fmt(unaShare.data, dU)} {symU}</strong>
          <small>TVL: {fmt(totalAssets as bigint | undefined, dU)} {symU}</small>
        </div>
      </section>

      <section className="panel">
        <h2>Depositar</h2>
        <label>
          Monto en {symU}
          <div className="fila">
            <input
              inputMode="decimal"
              placeholder="0,00"
              value={monto}
              onChange={(e) => setMonto(e.target.value.replace(',', '.'))}
              disabled={ocupado}
            />
            <button className="secundario" onClick={() => balU && setMonto(formatUnits(balU, dU))} disabled={ocupado}>
              Máx
            </button>
          </div>
        </label>
        <p className="preview">
          Vas a recibir: <strong>{assets ? fmt(preview.data, dS) : '—'} {symS}</strong>
        </p>
        {saldoInsuficiente && <p className="error">Saldo de {symU} insuficiente.</p>}
        <div className="fila">
          <button onClick={approve} disabled={ocupado || !assets || saldoInsuficiente || !necesitaApprove}>
            1. Approve
          </button>
          <button onClick={deposit} disabled={ocupado || !assets || saldoInsuficiente || necesitaApprove}>
            2. Deposit
          </button>
        </div>
      </section>

      <section className="panel">
        <h2>Retirar</h2>
        <p>
          Redimir todas tus shares ({fmt(balS, dS)} {symS}) por ≈ {fmt(previewRedeem.data, dU)} {symU}.
        </p>
        <button onClick={redeem} disabled={ocupado || !balS}>
          Redeem
        </button>
      </section>

      {estado && <p className="estado">{estado}</p>}
      {error && <p className="error">{error}</p>}
    </>
  )
}
