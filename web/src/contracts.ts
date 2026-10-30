import { erc20Abi, erc4626Abi, parseAbi, type Address } from 'viem'
import { anvil } from 'wagmi/chains'
import addresses from './addresses.json'

// addresses.json lo escribe script/Deploy.s.sol.
if (addresses.chainId !== anvil.id) {
  throw new Error(`addresses.json es de la chain ${addresses.chainId}, se esperaba ${anvil.id}`)
}

export const usdc = {
  address: addresses.mockUSDC as Address,
  abi: erc20Abi,
} as const

// erc4626Abi de viem no incluye la metadata ERC-20 de las shares.
const shareMetadataAbi = parseAbi([
  'function decimals() view returns (uint8)',
  'function symbol() view returns (string)',
])

export const vault = {
  address: addresses.simpleVault as Address,
  abi: [...erc4626Abi, ...shareMetadataAbi],
} as const
