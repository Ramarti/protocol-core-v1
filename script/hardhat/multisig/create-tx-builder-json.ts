import * as fs from 'fs';
import ethers, { Contract, JsonRpcProvider, id } from "ethers"
import hre from 'hardhat';
import path from 'path';

enum MethodType {
    SCHEDULE,
    UPGRADE
}

interface ContractAddresses {
    [key: string]: {
        [key: string]: string;
    };
}

interface GnosisSafeTransaction {
    to: string;
    value: string;
    data: string | null;
    contractMethod: {
        inputs: {
            name: string;
            type: string;
            internalType: string;
        }[];
        name: string;
        payable: boolean;
    };
    contractInputsValues: {
        [key: string]: string;
    };
}

interface GnosisSafeSchedule {
    version: string;
    chainId: string;
    createdAt: number;
    meta: {
        name: string;
        description: string;
        txBuilderVersion: string;
        createdFromSafeAddress: string;
        createdFromOwnerAddress: string;
        checksum: string;
    };
    transactions: GnosisSafeTransaction[];
}

interface ContractMethodInput {
    name: string;
    type: string;
    internalType: string;
}

interface ContractMethod {
    inputs: ContractMethodInput[];
    name: string;
    payable: boolean;
}

interface ContractInputsValues {
    target: string;
    data: string;
    when: string;
}


function getContractMethod(methodType: MethodType, proxyAddress: string, newImplAddress: string): (contractMethod: ContractMethod, contractInputsValues: ContractInputsValues) {
    let contractMethod: ContractMethod;
    let contractInputsValues: ContractInputsValues;
    /*
    switch (methodType:) {
        case MethodType.SCHEDULE:
            contractMethod = ContractMethod({
                inputs: [
                    { name: "target", type: "address", internalType: "address" },
                    { name: "data", type: "bytes", internalType: "bytes" },
                    { name: "when", type: "uint48", internalType: "uint48" }
                ],
                name: "schedule",
                payable: false
            });
            new ethers.Interface([
                "function schedule(address target, bytes data, uint48 when) external"
            ]).encodeFunctionData("schedule", [newImplAddress, getMethodData(MethodType.UPGRADE, newImplAddress) , "0"]);
            break;
        case MethodType.UPGRADE:
            new ethers.Interface([
                "function upgradeTo(address newImplementation) external"
            ]).encodeFunctionData("upgradeTo", [newImplAddress]);
            break;
        default:
            throw new Error(`Invalid method type: ${methodType}`);
    }*/

    switch (contractMethod) {
        case value:
            
            break;
    
        default:
            break;
    }

    /*contractMethod: {
        inputs: [
            { name: "target", type: "address", internalType: "address" },
            { name: "data", type: "bytes", internalType: "bytes" },
            { name: "when", type: "uint48", internalType: "uint48" }
        ],
        name: "schedule",
        payable: false
    },
    contractInputsValues: {
        target: newImplAddress,
        data: data,
        when: "0"
    }*/
    return (contractMethod, contractInputsValues);
}


function generateGnosisSafeTx(accessManagerAddress: string, methodType: MethodType, proxyAddress: string, newImplAddress: string): GnosisSafeTransaction {
    
    let (contractMethod, contractInputValues) = getContractMethod(methodType, proxyAddress, newImplAddress);

    return {
        to: methodType === MethodType.SCHEDULE ? proxyAddress : accessManagerAddress,
        value: "0",
        data: null,
        contractMethod: getContractMethod,
        contractInputsValues: contractInputValues
    };
}

function processContracts(inputJson: ContractAddresses): GnosisSafeTransaction[] {
    const transactions: GnosisSafeTransaction[] = [];

    for (const [, contracts] of Object.entries(inputJson)) {
        for (const [contractName, address] of Object.entries(contracts)) {
            if (contractName.endsWith('-Proxy')) {
                const baseName = contractName.replace('-Proxy', '');
                const newImplName = `${baseName}-NewImpl`;
                if (contracts[newImplName]) {
                    transactions.push(generateGnosisSafeTx(address, contracts[newImplName]));
                }
            }
        }
    }

    return transactions;
}

function generateChecksum(transactions: GnosisSafeTransaction[]): string {
    const txs: string = JSON.stringify(transactions)
    return id(txs);
}
export const rootPath = () => path.resolve(__dirname, '../../../deploy-out');

async function main() {
    const networkName = hre.network.name.toUpperCase();
    const provider = new JsonRpcProvider((hre.network.config as { url: string }).url)
    const chainId = (await provider.getNetwork()).chainId;

    // These would typically come from command line arguments or environment variables
    const inputFile = `${rootPath()}/upgrade-1.1.0-${chainId}.json`;
    const outputFile = 'gnosis_safe_schedule.json';
    const safeAddress = process.env[`${networkName}_SAFE_ADDRESS`]!;
    const mode

    const inputJson: ContractAddresses = JSON.parse(fs.readFileSync(inputFile, 'utf-8'));
    const transactions = processContracts(inputJson);

    const schedule: GnosisSafeSchedule = {
        version: "1.0",
        chainId: chainId.toString(),
        createdAt: Date.now(),
        meta: {
            name: "Lol",
            description: "",
            txBuilderVersion: "1.16.5",
            createdFromSafeAddress: safeAddress,
            createdFromOwnerAddress: "",
            checksum: generateChecksum(transactions)
        },
        transactions: transactions
    };

    fs.writeFileSync(outputFile, JSON.stringify(schedule, null, 2));
    console.log(`Gnosis Safe schedule has been generated and saved to ${outputFile}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });