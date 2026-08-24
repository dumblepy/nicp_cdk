import { useMemo } from 'preact/hooks';
import {
  getContract,
  type Address,
  type GetContractReturnType
} from 'viem';
import { publicClient } from './client';
import { type IcpWalletClient } from './icpWalletClient';
import counterAbi from '../../../../../../solidity/out/Counter.sol/Counter.json';

const COUNTER_CONTRACT_ADDRESS: Address = '0x5FbDB2315678afecb367f032d93F642f64180aa3' as Address;

export const useCounterContract = (walletClient: IcpWalletClient | null) => {
  const contract = useMemo(() => {
    if (!walletClient) {
      // walletClientがない場合は、読み取り専用のcontractを返す
      return getContract({
        address: COUNTER_CONTRACT_ADDRESS,
        abi: counterAbi.abi,
        client: publicClient,
      });
    }

    // walletClientがある場合は、読み書き可能なcontractを返す
    return getContract({
      address: COUNTER_CONTRACT_ADDRESS,
      abi: counterAbi.abi,
      client: {
        public: publicClient,
        wallet: walletClient,
      },
    });
  }, [walletClient]);

  return {
    contract,
    contractAddress: COUNTER_CONTRACT_ADDRESS,
  };
};
