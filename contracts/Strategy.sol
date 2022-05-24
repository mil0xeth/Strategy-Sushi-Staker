// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy,StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import {IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

interface ISushiBar is IERC20 {
    function enter(uint _amount) external;
    function leave(uint _share) external;
}

contract Strategy is BaseStrategy {
    using Address for address;

    ISushiBar public constant xSushi = ISushiBar(0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272);
    //Big number to guarantee sushiPerXSushi to account for all decimals without rounding:
    uint256 internal constant AVOID_ROUNDING_DECIMALS = 1e27;

    constructor(address _vault) public BaseStrategy(_vault) {
    }

    // ******** OVERRIDE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return "Strategy-xSushi-Staker";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfXSushi().mul(sushiPerXSushi()).div(AVOID_ROUNDING_DECIMALS).add(balanceOfWant());
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        uint256 totalDebt = vault.strategies(address(this)).totalDebt;
        uint256 totalAssetsAfterProfit = estimatedTotalAssets();
        _profit = totalAssetsAfterProfit > totalDebt
            ? totalAssetsAfterProfit.sub(totalDebt)
            : 0;

        uint256 _amountFreed;
        (_amountFreed, _loss) = liquidatePosition(_debtOutstanding.add(_profit));
        _debtPayment = Math.min(_debtOutstanding, _amountFreed);
        //Net profit and loss calculation
        if (_loss > _profit) {
            _loss = _loss.sub(_profit);
            _profit = 0;
        } else {
            _profit = _profit.sub(_loss);
            _loss = 0;
        }

    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 wantBalance = balanceOfWant();
        _checkAllowance(address(xSushi), address(want), wantBalance);
        xSushi.enter(balanceOfWant());
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 wantBalance = balanceOfWant();
        if (wantBalance < _amountNeeded){
            //Unstake xSushi amount in want corresponding to _amountNeeded (or total balance of xSushi (unlikely))
            xSushi.leave(Math.min(balanceOfXSushi(), _amountNeeded.sub(wantBalance).mul(AVOID_ROUNDING_DECIMALS).div(sushiPerXSushi())));
            _liquidatedAmount = Math.min(balanceOfWant(), _amountNeeded);
            _loss = _amountNeeded > _liquidatedAmount ? _amountNeeded.sub(_liquidatedAmount) : 0;
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        xSushi.leave(balanceOfXSushi());
        return balanceOfWant();
    }

    function prepareMigration(address _newStrategy) internal override {
        uint256 xSushiBalance = balanceOfXSushi();
        xSushi.transfer(_newStrategy, xSushiBalance);
    }

    function protectedTokens() internal view override returns (address[] memory){}

    function ethToWant(uint _amtInWei) public view override returns (uint){return _amtInWei;}

    /////////////////// HELPERS:

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _contract) < _amount) {
            IERC20(_token).safeApprove(_contract, 0);
            IERC20(_token).safeApprove(_contract, type(uint256).max);
        }
    }


    /////////////////// GETTERS:

    function balanceOfWant() public view returns (uint256){
        return want.balanceOf(address(this));
    }

    function balanceOfXSushi() public view returns (uint256){
        return xSushi.balanceOf(address(this));
    }

    function sushiPerXSushi() public view returns (uint256){
        return want.balanceOf(address(xSushi)).mul(AVOID_ROUNDING_DECIMALS).div(xSushi.totalSupply());
    }

    ////////////////// EMERGENCY UNSTAKE:

    function emergencyUnstakeXSushi(uint256 _amount) external onlyEmergencyAuthorized {
        xSushi.leave(_amount);
    }




}
