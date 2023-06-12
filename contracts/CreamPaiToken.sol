// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@thirdweb-dev/contracts/base/ERC20Base.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

/*
 * Website: https://creampai.org
 * Litepaper: https://creampai-org.gitbook.io/creampai/
 * Twitter: https://twitter.com/Real_CreamPAI
 * Telegram: t.me/real_creampai
 * OnlyFans: https://onlyfans.com/real_creampai
*/
contract CreamPaiToken is ERC20Base {
    string private _name = "CreamPAI";
    string private _symbol = "PAI";
    uint8 private _decimals = 18;
    uint256 private _supply = 69000000000;


    uint256 public taxForLiquidity = 47;
    uint256 public sellTaxForMarketing = 47;
    uint256 public buyTaxForMarketing = 47;
    uint256 public maxTxAmount = 690000000 * 10 ** _decimals;
    uint256 public maxWalletAmount = 690000000 * 10 ** _decimals;
    address public marketingWallet = 0x7Dd8271a9441f4dd9D6344571a626ec9fC167972;
    address public DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public _marketingReserves = 0;

    
    mapping(address => bool) public _isExcludedFromFee;
    uint256 public numTokensSellToAddToLiquidity = 1380000 * 10 ** _decimals;
    uint256 public numTokensSellToAddToETH = 690000 * 10 ** _decimals;
    event ExcludedFromFeeUpdated(address _address, bool _status);
    event PairUpdated(address _address);

    mapping (address => bool) public whitelisted;
    bool public publicTradingActive = false;
    event SetWhitelisted(address _address, bool _isExempt);
    event PublicTradingStarted();

    
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public uniswapV2Pair;

    bool inSwapAndLiquify;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor() ERC20Base(_name, _symbol) {
        _mint(msg.sender, (_supply * 10 ** _decimals));

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;

        _isExcludedFromFee[address(uniswapV2Router)] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[msg.sender] = true;
        _isExcludedFromFee[marketingWallet] = true;

        whitelisted[msg.sender] = true;
        whitelisted[address(this)] = true;
    }

    function updatePair(address _pair) external onlyOwner {
        require(_pair != DEAD, "LP Pair cannot be DEAD");
        require(
            _pair != address(0),
            "LP Pair cannot be 0!"
        );
        uniswapV2Pair = _pair;
        emit PairUpdated(_pair);
    }

    function setWhitelisted(address _address, bool _isWhitelisted) external onlyOwner {
        require(_address != address(0), "Zero Address");
        whitelisted[_address] = _isWhitelisted;
        emit SetWhitelisted(_address, _isWhitelisted);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "Cannot transfer to 0");
        require(to != address(0), "Cannot transfer from 0");
        require(
            balanceOf(from) >= amount,
            "Amount exceeds balance"
        );

        if(whitelisted[from] || whitelisted[to]){
            super._transfer(from,to,amount);
            return;
        }

        require(publicTradingActive, "Trading not active");

        if (
            (from == uniswapV2Pair || to == uniswapV2Pair) && !inSwapAndLiquify
        ) {
            if (from != uniswapV2Pair) {
                uint256 contractLiquidityBalance = balanceOf(address(this)) -
                    _marketingReserves;
                if (contractLiquidityBalance >= numTokensSellToAddToLiquidity) {
                    _swapAndLiquify(numTokensSellToAddToLiquidity);
                }
                if ((_marketingReserves) >= numTokensSellToAddToETH) {
                    _swapTokensForEth(numTokensSellToAddToETH);
                    _marketingReserves -= numTokensSellToAddToETH;
                    bool sent = payable(marketingWallet).send(
                        address(this).balance
                    );
                    require(sent, "Failed to send ETH");
                }
            }

            uint256 transferAmount;
            if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
                transferAmount = amount;
            } else {
                require(
                    amount <= maxTxAmount,
                    "ERC20: transfer amount exceeds the max transaction amount"
                );
                if (from == uniswapV2Pair) {
                    require(
                        (amount + balanceOf(to)) <= maxWalletAmount,
                        "ERC20: balance amount exceeded max wallet amount limit"
                    );
                }
                uint256 taxForMarketing = 0;

                // token purchase
                if (from == uniswapV2Pair) {
                    taxForMarketing = buyTaxForMarketing;
                } 
                // token sale
                else if (to == uniswapV2Pair) {
                    taxForMarketing = sellTaxForMarketing;
                }

                uint256 marketingShare = ((amount * taxForMarketing) / 100);
                uint256 liquidityShare = ((amount * taxForLiquidity) / 100);
                transferAmount = amount - (marketingShare + liquidityShare);
                _marketingReserves += marketingShare;

                super._transfer(
                    from,
                    address(this),
                    (marketingShare + liquidityShare)
                );
            }
            super._transfer(from, to, transferAmount);
        } else {
            super._transfer(from, to, amount);
        }
    }

    function enablePublicTrading() external onlyOwner {
        publicTradingActive = true;
        emit PublicTradingStarted();
    }

    function excludeFromFee(address _address, bool _status) external onlyOwner {
        _isExcludedFromFee[_address] = _status;
        emit ExcludedFromFeeUpdated(_address, _status);
    }

    function _swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        uint256 half = (contractTokenBalance / 2);
        uint256 otherHalf = (contractTokenBalance - half);

        uint256 initialBalance = address(this).balance;

        _swapTokensForEth(half);

        uint256 newBalance = (address(this).balance - initialBalance);

        _addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function _swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(
        uint256 tokenAmount,
        uint256 ethAmount
    ) private lockTheSwap {
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            marketingWallet,
            block.timestamp
        );
    }

    function changeMarketingWallet(
        address newWallet
    ) public onlyOwner returns (bool) {
        require(newWallet != DEAD, "LP Pair cannot be DEAD");
        require(
            newWallet != address(0),
            "LP Pair cannot be 0"
        );
        marketingWallet = newWallet;
        return true;
    }

    function changeTaxForLiquidityAndMarketing(
        uint256 _taxForLiquidity,
        uint256 _buyTaxForMarketing,
        uint256 _sellTaxForMarketing
    ) public onlyOwner returns (bool) {
        require(
            (_taxForLiquidity + _buyTaxForMarketing) <= 10,
            "Max tax is 10%"
        );
        require(
            (_taxForLiquidity + _sellTaxForMarketing) <= 10,
            "Max tax is 10%"
        );
        taxForLiquidity = _taxForLiquidity;
        buyTaxForMarketing = _buyTaxForMarketing;
        sellTaxForMarketing = _sellTaxForMarketing;

        return true;
    }

    function changeSwapThresholds(
        uint256 _numTokensSellToAddToLiquidity,
        uint256 _numTokensSellToAddToETH
    ) public onlyOwner returns (bool) {
        require(
            _numTokensSellToAddToLiquidity < _supply / 98,
            "Max 2% of total supply"
        );
        require(
            _numTokensSellToAddToETH < _supply / 98,
            "Max 2% of total supply"
        );
        numTokensSellToAddToLiquidity =
            _numTokensSellToAddToLiquidity *
            10 ** _decimals;
        numTokensSellToAddToETH = _numTokensSellToAddToETH * 10 ** _decimals;

        return true;
    }

    function changeMaxTxAmount(
        uint256 _maxTxAmount
    ) public onlyOwner returns (bool) {
        maxTxAmount = _maxTxAmount;

        return true;
    }

    function changeMaxWalletAmount(
        uint256 _maxWalletAmount
    ) public onlyOwner returns (bool) {
        maxWalletAmount = _maxWalletAmount;

        return true;
    }

    receive() external payable {}
}
