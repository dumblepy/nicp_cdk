import { hydrate, prerender as ssr } from 'preact-iso';
import { useState, useEffect } from 'preact/hooks';
import { Address, verifyMessage, http } from 'viem';
import { anvil } from 'viem/chains';
import { useIcpAuth } from './hooks/icpAuth';
import { createIcpWalletClient, type IcpWalletClient } from './hooks/icpWalletClient';
import { useCounterContract } from './hooks/useCounterContract';

export function App() {
	const { authClient, isAuthenticated, isLoading, principal, login, logout } = useIcpAuth();
	const [walletClient, setWalletClient] = useState<IcpWalletClient | null>(null);
	const [accountAddress, setAccountAddress] = useState<Address | null>(null);
	const [message, setMessage] = useState<string>('hello world');
	const [signature, setSignature] = useState<string | null>(null);
	const [isValid, setIsValid] = useState<boolean | null>(null);
	const [counterValue, setCounterValue] = useState<bigint | null>(null);
	const [number, setNumber] = useState<bigint | null>(null);
	
	// カスタムフックでcounterContractを管理
	const { contract: counterContract, contractAddress } = useCounterContract(walletClient);

	useEffect(() => {
		if (!authClient || !isAuthenticated) {
			setWalletClient(null);
			setAccountAddress(null);
			return;
		}

		let cancelled = false;

		// 非同期関数を明示的に定義
		const initializeWallet = async () => {
			try {
				// ICPキャニスター経由で署名を行うLocalAccountを直接作成
				const walletClient = await createIcpWalletClient({
					authClient,
					chain: anvil,
					transport: http('http://localhost:8545'),
				});
				
				if (cancelled) {
					return;
				}
				
				setWalletClient(walletClient);
				setAccountAddress(walletClient.account.address);
				console.log('ICP Account created successfully:', walletClient.account.address);
			} catch (error) {
				if (!cancelled) {
					console.error('Failed to create ICP account:', error);
					setWalletClient(null);
					setAccountAddress(null);
				}
			}
		};

		initializeWallet();

		return () => {
			cancelled = true;
		};
	}, [authClient, isAuthenticated]);

	const handleAuth = async () => {
		if (isAuthenticated) {
			await logout();
			setWalletClient(null);
			setAccountAddress(null);
			setSignature(null);
			setIsValid(null);
			return;
		}

		await login();
	};

	const handleSign = async () => {
		if (!walletClient || !accountAddress) {
			return;
		}

		try {
			const signed = await walletClient.signMessage({
				account: walletClient.account,
				message,
			});
			setSignature(signed);
			// クライアント側で署名検証
			const verified = await verifyMessage({
				address: accountAddress,
				message,
				signature: signed,
			});
			setIsValid(verified);
		} catch (error) {
			console.error('Failed to sign message:', error);
			setSignature(null);
			setIsValid(null);
		}
	};

	const readCounterValue = async () => {
		if (!counterContract) {
			return;
		}
		try {
			const value = await counterContract.read.number();
			setCounterValue(value as bigint);
		} catch (error) {
			console.error('Failed to read counter value:', error);
			setCounterValue(null);
		}
	};

	const handleIncrement = async () => {
		if (!walletClient || !counterContract) {
			return;
		}
		try {
			const hash = await counterContract.write.increment();
			console.log('Transaction hash:', hash);
			// インクリメント後にカウンター値を再読み込み
			await readCounterValue();
		} catch (error) {
			console.error('Failed to increment counter:', error);
		}
	};

	const handleSetNumber = async () => {
		if (!walletClient || !counterContract || number === null) {
			return;
		}
		try {
			const hash = await counterContract.write.setNumber([number]);
			console.log('Transaction hash:', hash);
			// 設定後にカウンター値を再読み込み
			await readCounterValue();
		} catch (error) {
			console.error('Failed to set number:', error);
		}
	};

	// BigInt変換のエラーハンドリングを追加
	const handleNumberInput = (e: Event) => {
		const target = e.target as HTMLInputElement;
		const value = target.value.trim();
		
		if (value === '') {
			setNumber(null);
			return;
		}
		
		try {
			setNumber(BigInt(value));
		} catch (error) {
			console.error('Invalid number input:', error);
			// 無効な入力の場合は現在の値を保持
		}
	};

	return (
		<main>
			<article>
				<h2>T-ECDSA</h2>
				<button onClick={handleAuth} disabled={isLoading || !authClient}>
					{isAuthenticated ? 'Logout' : 'Login with Internet Identity'}
				</button>
				<p>Status: {isLoading ? 'Checking…' : isAuthenticated ? 'Authenticated' : 'Not authenticated'}</p>
				{isAuthenticated && (
					<>
						<p>Principal: {principal}</p>
						<p>Account Address: {accountAddress}</p>
						<p>Counter Contract: {contractAddress}</p>
						<p>Contract Ready: {counterContract ? 'Yes' : 'No'}</p>
					</>
				)}
				<hr />
				<input
					type="text"
					placeholder="Message"
					onInput={(e) => setMessage((e.target as HTMLInputElement).value)}
					value={message}
				/>
				<button onClick={handleSign} disabled={!walletClient || !accountAddress}>
					Sign
				</button>
				<p>Signature: {signature}</p>
				<p>isValid: {isValid !== null ? isValid.toString() : 'Not verified yet'}</p>
				<hr />
				<button onClick={readCounterValue}>
					Read Counter
				</button>
				<button onClick={handleIncrement} disabled={!walletClient || !counterContract}>
					+
				</button>
				<button onClick={handleSetNumber} disabled={!walletClient || !counterContract || number === null}>
					set
				</button>
				<input
					type="number"
					placeholder="Number"
					onInput={handleNumberInput}
					value={number?.toString() ?? ''}
				/>
				<p>Counter: {counterValue !== null ? counterValue.toString() : 'Not read yet'}</p>
			</article>
		</main>
	);
}

if (typeof window !== 'undefined') {
	hydrate(<App />, document.getElementById('app'));
}

export async function prerender(data) {
	return await ssr(<App {...data} />);
}
