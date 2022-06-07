// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../interface/IUniswapV2Router.sol';
import '../interface/IUniswapV2Factory.sol';
import '../interface/IUniswapV2Pair.sol';
import "../tool/Operator.sol";
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Liquidity is Operator {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct addRecord {
        bool exists;
        uint256 id;
        uint256 addType;
        uint256 amountLP;
        uint256 status;
        uint256 canRansomTime;
        uint256 ransomTime;
        uint256 amountOSPD;
        uint256 amountWithdraw;
    }
    mapping(address => addRecord[]) addRecords;

    uint256 public lockReleaseCycle;
    uint256 public lockReleaseTimes;
    uint256 public addTime;

    address payable wallet;
    address public ospdAddPool;
    address public ospdWithdrawPool;
    address public lpWallet;
    uint256 public cutRate;
    uint256 public ospdSource;

    IERC20 constant USDT = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IERC20 constant OSPD = IERC20(0x73F3228226cD1cDFD42834240AE9C33F2fbf876A);
    IUniswapV2Router02 constant ur = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IUniswapV2Factory constant uf = IUniswapV2Factory(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73);

    event AddLiquidity(
        address indexed account,
        uint256 indexed addType,
        uint256 indexed id,
        uint256 amount,
        uint256 amountETHAdd,
        uint256 amountLP,
        uint256 canRansomTime
    );
    event Ransom(address indexed account, uint256 indexed id, uint256 amountOSPD);
    event Withdraw(address indexed account, uint256 indexed id, uint256 amount, uint256 lockAmount);

    constructor(
        address payable wallet_, 
        address ospdAddPool_, 
        address ospdWithdrawPool_, 
        address lpWallet_, 
        uint256 cutRate_
    ) {
        wallet = wallet_;
        ospdAddPool = ospdAddPool_;
        ospdWithdrawPool = ospdWithdrawPool_;
        cutRate = cutRate_;
        lpWallet = lpWallet_;
        ospdSource = 0;

        lockReleaseCycle = 86400;
        lockReleaseTimes = 30;
        addTime = 86400 * 45;
    }

    receive() external payable {}

    function setWallet(address payable newWallet) external onlyOperator {
        wallet = newWallet;
    }

    function setOspdPool(address newOspdAddPool, address newOspdWithdrawPool) external onlyOperator {
        ospdAddPool = newOspdAddPool;
        ospdWithdrawPool = newOspdWithdrawPool;
    }

    function setCutRate(uint256 newRate) external onlyOperator {
        cutRate = newRate;
    }

    function setLock(uint256 lockReleaseCycle_, uint256 lockReleaseTimes_, uint256 addTime_) external onlyOperator {
        lockReleaseCycle = lockReleaseCycle_;
        lockReleaseTimes = lockReleaseTimes_;
        addTime = addTime_;
    }

    function setLpWallet(address newLpWallet) external onlyOperator {
        lpWallet = newLpWallet;
    }

    function setOspdSource(uint256 newOspdSource) external onlyOperator {
        ospdSource = newOspdSource;
    }

    function addLiquidityUSDT(address user, uint256 amount) external {
        USDT.safeTransferFrom(msg.sender, address(this), amount);
        uint256 initAmount = amount;
        if (ospdSource == 1 && cutRate > 0) {
            uint256 amountCut = amount.mul(cutRate).div(1000);
            amount = amount.sub(amountCut);
            USDT.safeTransfer(wallet, amountCut);
        }
        uint256 half = amount.div(2);
        amount = amount.sub(half);

        USDT.safeApprove(address(ur), amount);
        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = ur.WETH();
        uint256[] memory amountETHs = ur.swapExactTokensForETH(amount, 0, path, address(this), block.timestamp);
        uint256 amountETH = amountETHs[amountETHs.length - 1];

        (uint256 reserveOSPD, uint256 reserveETH,) = IUniswapV2Pair(uf.getPair(address(OSPD), ur.WETH())).getReserves();
        uint256 amountOSPD = ur.quote(amountETH, reserveETH, reserveOSPD);
        if (ospdSource == 1) {
            address[] memory path2 = new address[](3);
            path2[0] = address(USDT);
            path2[1] = ur.WETH();
            path2[2] = address(OSPD);
            USDT.safeApprove(address(ur), half);
            ur.swapExactTokensForTokens(half, 0, path2, address(this), block.timestamp);
            amountOSPD = OSPD.balanceOf(address(this)).sub(1);
        } else {
            USDT.safeTransfer(wallet, half);
            OSPD.safeTransferFrom(ospdAddPool, address(this), amountOSPD);
        }

        OSPD.safeApprove(address(ur), amountOSPD);
        (, uint256 amountETHAdd, uint256 liquidity) = ur.addLiquidityETH{value:amountETH}(
            address(OSPD), amountOSPD, 0, 0, lpWallet, block.timestamp
        );

        if (OSPD.balanceOf(address(this)) > 1) {
            OSPD.safeTransfer(ospdWithdrawPool, OSPD.balanceOf(address(this)));
        }
        if (address(this).balance > 0) {
            wallet.transfer(address(this).balance);
        }

        addRecord storage ar = addRecords[user].push();
        ar.exists = true;
        ar.id = addRecords[user].length - 1;
        ar.addType = 1;
        ar.amountLP = liquidity;
        ar.canRansomTime = block.timestamp.add(addTime);

        emit AddLiquidity(user, 1, ar.id, initAmount, amountETHAdd, liquidity, ar.canRansomTime);
    }

    function addLiquidityETH(address user) external payable {
        uint256 amount = msg.value;
        uint256 initAmount = amount;
        if (ospdSource == 1 && cutRate > 0) {
            uint256 amountCut = amount.mul(cutRate).div(1000);
            amount = amount.sub(amountCut);
            wallet.transfer(amountCut);
        }
        uint256 half = amount.div(2);
        uint256 amountETH = amount.sub(half);

        address weth = ur.WETH();
        address pairAddr = uf.getPair(address(OSPD), weth);
        (uint256 reserveOSPD, uint256 reserveETH,) = IUniswapV2Pair(pairAddr).getReserves();
        uint256 amountOSPD = ur.quote(amountETH, reserveETH, reserveOSPD);
        if (OSPD.balanceOf(ospdAddPool) < amountOSPD) {
            address[] memory path2 = new address[](2);
            path2[0] = weth;
            path2[1] = address(OSPD);
            ur.swapExactETHForTokens{value:half}(0, path2, address(this), block.timestamp);
            amountOSPD = OSPD.balanceOf(address(this)).sub(1);
        } else {
            OSPD.safeTransferFrom(ospdAddPool, address(this), amountOSPD);
            wallet.transfer(half);
        }

        OSPD.safeApprove(address(ur), amountOSPD);
        (, uint256 amountETHAdd, uint256 liquidity) = ur.addLiquidityETH{value:amountETH}(
            address(OSPD), amountOSPD, 0, 0, lpWallet, block.timestamp
        );

        if (OSPD.balanceOf(address(this)) > 1) {
            OSPD.safeTransfer(ospdWithdrawPool, OSPD.balanceOf(address(this)));
        }
        if (address(this).balance > 0) {
            wallet.transfer(address(this).balance);
        }

        addRecord storage ar = addRecords[user].push();
        ar.exists = true;
        ar.id = addRecords[user].length - 1;
        ar.addType = 0;
        ar.amountLP = liquidity;
        ar.canRansomTime = block.timestamp.add(addTime);

        emit AddLiquidity(user, 0, ar.id, initAmount, amountETHAdd, liquidity, ar.canRansomTime);
    }

    function ransom(uint256 id) external {
        require(id < addRecords[msg.sender].length, "not exists");
        require(addRecords[msg.sender][id].canRansomTime <= block.timestamp, "cannot ransom yet");
        require(addRecords[msg.sender][id].status == 0, "ransomed");

        address weth = ur.WETH();
        address pairAddr = uf.getPair(address(OSPD), weth);
        IUniswapV2Pair(pairAddr).approve(address(ur), addRecords[msg.sender][id].amountLP);
        IUniswapV2Pair(pairAddr).transferFrom(lpWallet, address(this), addRecords[msg.sender][id].amountLP);
        uint256 amountETH = ur.removeLiquidityETHSupportingFeeOnTransferTokens(address(OSPD),
            addRecords[msg.sender][id].amountLP, 0, 0, address(this), block.timestamp);
        uint256 amountToken = OSPD.balanceOf(address(this)).sub(1);
        uint256 totalAmount = 0;
        OSPD.safeTransfer(ospdWithdrawPool, amountToken);
        if (ospdSource == 0) {
            OSPD.safeTransferFrom(ospdAddPool, ospdWithdrawPool, amountToken);
            wallet.transfer(address(this).balance);
            totalAmount = amountToken.mul(2);
        } else {
            address[] memory path = new address[](2);
            path[0] = weth;
            path[1] = address(OSPD);
            ur.swapExactETHForTokens{value:amountETH}(0, path, address(this), block.timestamp);
            totalAmount = amountToken.add(OSPD.balanceOf(address(this)).sub(1));
            OSPD.safeTransfer(ospdWithdrawPool, OSPD.balanceOf(address(this)));
        }
        addRecords[msg.sender][id].status = 1;
        addRecords[msg.sender][id].ransomTime = block.timestamp;
        addRecords[msg.sender][id].amountOSPD = totalAmount;

        emit Ransom(msg.sender, id, totalAmount);
    }

    function withdraw(uint256 id, uint256 amount) external {
        require(id < addRecords[msg.sender].length, "not exists");
        require(addRecords[msg.sender][id].status == 1, "cannot");

        uint256 lockAmount = getLockAmount(msg.sender, id);
        addRecords[msg.sender][id].amountWithdraw = addRecords[msg.sender][id].amountWithdraw.add(amount);
        require(lockAmount.add(addRecords[msg.sender][id].amountWithdraw) <= addRecords[msg.sender][id].amountOSPD, "too much amount");

        OSPD.safeTransferFrom(ospdWithdrawPool, msg.sender, amount);

        emit Withdraw(msg.sender, id, amount, lockAmount);
    }

    function getAvaliableAmount(address account, uint256 id) public view returns (uint256) {
        if (id >= addRecords[account].length) {
            return 0;
        }
        if (addRecords[account][id].status == 0) {
            return 0;
        }

        return addRecords[account][id].amountOSPD.sub(getLockAmount(account, id)).sub(addRecords[account][id].amountWithdraw);
    }

    function getLockAmount(address account, uint256 id) public view returns (uint256) {
        if (id >= addRecords[account].length) {
            return 0;
        }
        if (addRecords[account][id].status == 0) {
            return 0;
        }
        uint256 amount = addRecords[account][id].amountOSPD;
        uint256 startTime = addRecords[account][id].ransomTime;
        if (startTime >= block.timestamp) {
            return amount;
        }
        uint256 endTime = startTime.add(lockReleaseCycle.mul(lockReleaseTimes));
        if (endTime <= block.timestamp) {
            return 0;
        }
        uint256 releasedTimes = block.timestamp.sub(startTime).div(lockReleaseCycle);
        return amount.sub(releasedTimes.mul(amount).div(lockReleaseTimes));
    }

    function getRecord(address account, uint256 id) external view returns (addRecord memory) {
        return addRecords[account][id];
    }
}