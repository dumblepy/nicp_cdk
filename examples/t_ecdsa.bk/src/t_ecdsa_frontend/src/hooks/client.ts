import { createPublicClient, http } from 'viem';
import { anvil } from 'viem/chains';

export const publicClient = createPublicClient({
  chain: anvil,
  transport: http('http://localhost:8545'),
})