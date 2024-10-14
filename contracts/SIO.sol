// SPDX-License-Identifier: MIT

/*

    This is the official SIO Router used by the SIO Smart Wallet.

    Website: https://sio.finance/
    Docs: https://docs.sio.finance/
    X: https://x.com/siodotfinance/
    Telegram: https://t.me/SIO_Finance/

*/

pragma solidity 0.8.28;

interface IUniswapV2Router {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function token0() external view returns (address);
}

interface IUniswapV2Pair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

contract SIO {
    
    ///////////////////////////////// CONSTANTS /////////////////////////////////////////////////////////////////

    address constant WETH_CONTRACT = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9; // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    address constant UNIV2_ROUTER_CONTRACT = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008; // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    address constant UNIV2_FACTORY_CONTRACT = 0x7E0987E5b3a30e3f2828572Bb659A548460a3003; // 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f

    bytes4 constant ERC20_TRANSFER_ID = 0xa9059cbb;         // transfer(address,uint256)
    bytes4 constant ERC20_TRANSFERFROM_ID = 0x23b872dd;     // transferFrom(address,address,uint256)
    //bytes4 constant UNIV2_GETAMOUNTSOUT_ID = 0xd06ca61f;    // getAmountsOut(uint256,address[])
    //bytes4 constant PAIR_SWAP_ID = 0x022c0d9f;              // swap(uint,uint,address,bytes)
    bytes4 constant WETH_DEPOSIT_ID = 0xd0e30db0;           // deposit()
    bytes4 constant ERC20_BALANCEOF_ID = 0x70a08231;        // balanceOf(address)

    uint8 constant TRANSACTION_TYPE_BUY = 0;
    uint8 constant TRANSACTION_TYPE_SELL = 1;
    uint8 constant TRANSACTION_TYPE_SEND = 2;

    ///////////////////////////////// CONSTANTS /////////////////////////////////////////////////////////////////

    ///////////////////////////////// STORAGE ///////////////////////////////////////////////////////////////////

    uint256 public fee;
    address public owner;
    bool public contractStatus;

    ///////////////////////////////// STORAGE ///////////////////////////////////////////////////////////////////

    constructor() {
        owner = msg.sender;
        contractStatus = true;
        fee = 0.001 ether;
    }

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner);
        owner = newOwner;
    }

    function changeFee(uint256 newFee) external {
        require(msg.sender == owner);
        fee = newFee;
    }

    function changeContractStatus(bool status) external {
        require(msg.sender == owner);
        contractStatus = status;
    }

    function withdraw(address token) external {
        require(msg.sender == owner);
        assembly {
            mstore(0x7c, ERC20_BALANCEOF_ID)
            mstore(0x80, address())
            let success := staticcall(sub(gas(), 5000), token, 0x7c, 0x24, 0x00, 0x20)
            if iszero(success) {
                revert(3,3)
            }
            if eq(mload(0x00), 0) {
                revert(3,3)
            }
            let bal := mload(0x00)
            mstore(0x7c, ERC20_TRANSFER_ID)
            mstore(0x80, caller())
            mstore(0xA0, bal)
            success := call(sub(gas(), 5000), token, 0, 0x7c, 0x44, 0, 0)
            if iszero(success) {
                revert(3,3)
            }

            if iszero(eq(selfbalance(), 0)) { // Withdraw ETH
                success := call(sub(gas(), 5000), caller(), selfbalance(), 0, 0, 0, 0)
                if iszero(success) {
                    revert(3,3)
                }
            }
        }
    }

    function getBalance(address account, address token) public view returns(uint256) {
        assembly {
            mstore(0x7c, ERC20_BALANCEOF_ID)
            mstore(0x80, account)
            let success := staticcall(sub(gas(), 5000), token, 0x7c, 0x24, 0x00, 0x20)
            if iszero(success) {
                revert(3,3)
            }
            return(0x00, 0x20)
        }
    }

    receive() external payable { 
        assembly {
            if eq(callvalue(), 0) {
                revert(3,3)
            }
            let ptr := mload(0x40)
            mstore(ptr, WETH_DEPOSIT_ID)
            let success := call(sub(gas(), 5000), WETH_CONTRACT, callvalue(), ptr, 0x4, 0, 0)
            if iszero(success) {
                revert(3,3)
            }
        }
    }

    fallback() external payable {
        require(contractStatus, "Maintenance");
        uint256 value = msg.value;
        uint8 length;
        assembly {
            length := shr(248, calldataload(0x00))
        }
        address[] memory path;
        for(uint8 i = 0; i < length; i++) {
            address token;
            uint256 amount;
            uint8 transaction;

            assembly {
                token := shr(96, calldataload(add(mul(i,0x35), 0x01)))
                amount := calldataload(add(mul(i,0x35), 0x15))
                transaction := shr(248, calldataload(add(mul(i,0x35), 0x35)))

                switch transaction
                case 0 { // TRANSACTION_TYPE_BUY
                    path := mload(0x40)
                    mstore(path, 2)
                    mstore(add(path, 0x20), WETH_CONTRACT)
                    mstore(add(path, 0x40), token)
                    mstore(0x40, add(path, 0x60))
                }
                case 1 { // TRANSACTION_TYPE_SELL
                    path := mload(0x40)
                    mstore(path, 2)
                    mstore(add(path, 0x20), token)
                    mstore(add(path, 0x40), WETH_CONTRACT)
                    mstore(0x40, add(path, 0x60))
                }
            }
            if(transaction == TRANSACTION_TYPE_BUY) {
                value -= amount;
                assembly {
                    let ptr := mload(0x40)
                    mstore(ptr, WETH_DEPOSIT_ID)
                    let success := call(sub(gas(), 5000), WETH_CONTRACT, callvalue(), ptr, 0x4, 0, 0)
                    if iszero(success) {
                        revert(3,3)
                    }
                }
                uint256 amountout = IUniswapV2Router(UNIV2_ROUTER_CONTRACT).getAmountsOut(amount, path)[1];
                address pair = IUniswapV2Factory(UNIV2_FACTORY_CONTRACT).getPair(path[0], path[1]);
                address token0 = IUniswapV2Factory(pair).token0();
                uint8 order = (token0 == WETH_CONTRACT ? 1 : 0);
                assembly {
                    mstore(0x7c, ERC20_TRANSFER_ID)
                    mstore(0x80, pair)
                    mstore(0xA0, amount)
                    let success := call(sub(gas(), 5000), WETH_CONTRACT, 0, 0x7c, 0x44, 0, 0)
                    if iszero(success) {
                        revert(3,3)
                    }
                }
                IUniswapV2Pair(pair).swap(order == 0 ? amountout : 0, order == 1 ? amountout : 0, msg.sender, new bytes(0));
            }
            else if(transaction == TRANSACTION_TYPE_SELL) {
                uint256 amountout = IUniswapV2Router(UNIV2_ROUTER_CONTRACT).getAmountsOut(amount, path)[1];
                address pair = IUniswapV2Factory(UNIV2_FACTORY_CONTRACT).getPair(path[0], path[1]);
                address token0 = IUniswapV2Factory(pair).token0();
                uint8 order = (token0 == WETH_CONTRACT ? 0 : 1);
                assembly {
                    mstore(0x7c, ERC20_TRANSFERFROM_ID)
                    mstore(0x80, caller())
                    mstore(0xA0, pair)
                    mstore(0xC0, amount)
                    let success := call(sub(gas(), 5000), WETH_CONTRACT, 0, 0x7c, 0x64, 0, 0)
                    if iszero(success) {
                        revert(3,3)
                    }
                }
                IUniswapV2Pair(pair).swap(order == 0 ? amountout : 0, order == 1 ? amountout : 0, msg.sender, new bytes(0));
            }
            else if(transaction == TRANSACTION_TYPE_SEND) {
                // token becomes address in this case
                value -= amount;
                assembly {
                    let success := call(sub(gas(), 5000), token, amount, 0, 0, 0, 0)
                    if iszero(success) {
                        revert(3,3)
                    }
                }
            }
        }
        require(value >= fee*length, "Fee not paid");
    }
}