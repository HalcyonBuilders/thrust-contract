import { Ed25519Keypair, devnetConnection, JsonRpcProvider, RawSigner, TransactionBlock } from "@mysten/sui.js";
import dotenv from "dotenv";

// export const connection = new Connection({
//     // fullnode: "https://sui-testnet-endpoint.blockvision.org",
//     fullnode: "https://fullnode.testnet.sui.io",
//     faucet: "",
// });

dotenv.config();

export const keypair = Ed25519Keypair.fromSecretKey(Uint8Array.from(Buffer.from(process.env.KEY!, "base64")).slice(1));

export const provider = new JsonRpcProvider(devnetConnection);

export const signer = new RawSigner(keypair, provider);

export const tx = new TransactionBlock();

// ---------------------------------

// test
// export const PACKAGE_ID = "0x3f7724c72a7fec2996c1dd5bbbf8e13d59532e396c3c1eb9f0413505cfcf6629";
// export const DISPENSER = "0x7b4b9db80e7416aae9d24fe3065deecb8963ad6a64a67af1265625b1a82f47b3";
// export const ADMIN_CAP = "0xb5c35bac2a20d8bd305375ebd0c04e1655e0031e356c301b59f229f5a11e1837";

// main
export const PACKAGE_ID = "0x98c8b10337a98bc3f844253a6075e6db911948880346b989f6650364a09f76f0";
export const DISPENSER = "0x3811685776bedf4af159128144edd470e7ba28a3878c6884bfe5c83ee4dda635";
export const ADMIN_CAP = "0x08a57716ed0d4c965e5ae062f370f7a0e637ac4bcb017d26bca1f0013316b029";

// export const COLLECTION = "0x27150120370befb9851d54813576bcce0ff7b637efc4e603ba9f10ff1d434f50";

// ethos addr: 0x4a3af36df1b20c8d79b31e50c07686c70d63310e4f9fff8d9f8b7f4eb703a2fd

// cli addr: 0xb242bbfb17bbb802e242fcf033bb9c33ae349a0c2b48c8cb6b9a079acc20432f
