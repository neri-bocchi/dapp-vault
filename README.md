# Vault ERC-4626

Vault ERC-4626 de ejemplo para clase, con un frontend para depositar y retirar en una red local.

- `src/MockUSDC.sol`: token ERC-20 de prueba con 6 decimales (mUSDC).
- `src/SimpleVault.sol`: vault ERC-4626 sobre mUSDC (OpenZeppelin v5, offset de decimales 6).
- `script/Deploy.s.sol`: despliega ambos contratos en Anvil, mintea 10.000 mUSDC a la cuenta #0 y escribe las direcciones en `web/src/addresses.json`.
- `web/`: frontend en Vite + React + TypeScript + wagmi + viem.

## Requisitos

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `anvil`, `cast`)
- Node.js 20.19+ o 22.12+ (lo pide Vite) y npm

## Instalación

```shell
git clone --recurse-submodules https://github.com/neri-bocchi/dapp-vault.git
cd dapp-vault
cd web && npm install
```

Si clonaste sin `--recurse-submodules`, bajá las dependencias de Solidity con `git submodule update --init --recursive`.

## Contratos

```shell
forge build
forge test
```

## Correr el frontend

Hacen falta tres terminales, todas desde la raíz del repo.

**1. Levantar Anvil** (chainId 31337, en `http://127.0.0.1:8545`):

```shell
anvil
```

**2. Desplegar los contratos.** Usá la clave privada de la cuenta #0 que imprime Anvil al arrancar (es pública y sirve solo para uso local):

```shell
cp .env.example .env   # completar PRIVATE_KEY con la clave de la cuenta #0
source .env
forge script script/Deploy.s.sol --rpc-url anvil --private-key $PRIVATE_KEY --broadcast
```

El script actualiza `web/src/addresses.json`. Si reiniciás Anvil, la chain arranca de cero: volvé a desplegar.

**3. Levantar el frontend:**

```shell
cd web
npm run dev
```

Abrí la URL que muestra Vite (por defecto http://localhost:5173).

### Conectar una cuenta

La pantalla inicial ofrece dos opciones:

- **Cuenta local** (sin wallet): firma directo contra Anvil con la cuenta #0, que es la que recibió los 10.000 mUSDC. Para usar otra cuenta desbloqueada de Anvil:

  ```shell
  VITE_ACCOUNT=0x70997970C51812dC3A010C7d01b50e0d17dc79C8 npm run dev
  ```

- **Wallet del navegador** (MetaMask u otra): agregá una red con RPC `http://127.0.0.1:8545` y chainId `31337`, e importá la clave privada de la cuenta #0.

Una vez conectado podés aprobar y depositar mUSDC en el vault, y retirar (`redeem`) tus shares.

### Otros comandos del frontend

```shell
npm run build    # chequeo de tipos + build de producción en web/dist
npm run lint     # oxlint
npm run preview  # servir el build
```
