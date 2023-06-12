// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@thirdweb-dev/contracts/base/ERC20Base.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";


// Website: https://creampai.org
// Litepaper: https://creampai-org.gitbook.io/creampai/
// Twitter: https://twitter.com/Real_CreamPAI
// Telegram: https://t.me/CreamPAI_Portal
// OnlyFans: https://onlyfans.com/real_creampai
contract CreamPaiToken is ERC20Base {
    string private _name = "CreamPAI";
    string private _symbol = "PAI";
    uint8 private _decimals = 18;
    uint256 private _supply = 69000000000;

    address public marketingWallet = 0x6Fe13903740d78296D70252f8498d4B82f1fA671;
    address public DEAD = 0x000000000000000000000000000000000000dEaD;

    // Taxes
    uint256 public taxForLiquidity = 47;
    uint256 public sellTaxForMarketing = 47;
    uint256 public buyTaxForMarketing = 47;
    uint256 public numTokensSellToAddToLiquidity = 1380000 * 10 ** _decimals;
    uint256 public numTokensSellToAddToETH = 690000 * 10 ** _decimals;
    uint256 public _marketingReserves;

    // Max tx/wallet amounts
    uint256 public maxTxAmount = 690000000 * 10 ** _decimals;
    uint256 public maxWalletAmount = 690000000 * 10 ** _decimals;
    event MarketingWalletUpdated(address _address);
    event MaxWalletAmountUpdated(uint256 _amount);
    event MaxTransactionAmountUpdated(uint256 _amount);
    event TaxUpdated(
        uint256 _taxForLiquidity,
        uint256 _buyTaxForMarketing,
        uint256 _sellTaxForMarketing
    );

    // Whitelisting
    mapping(address => bool) public _isExcludedFromFee;
    event ExcludedFromFeeUpdated(address _address, bool _status);

    // Uniswap controls
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public uniswapV2Pair;
    bool public publicTradingActive;
    event PairUpdated(address _address);
    event PublicTradingStarted();
    event SwapThresholdUpdated(
        uint256 _numTokensSellToAddToLiquidity,
        uint256 _numTokensSellToAddToETH
    );

    bool private inSwapAndLiquify;

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

    // Contructor
    constructor() payable ERC20Base(_name, _symbol) {
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
    }

    // Update uniswap pair to check and tax
    function updatePair(address _pair) external onlyOwner {
        require(_pair != DEAD, "LP Pair cannot be DEAD");
        require(_pair != address(0), "LP Pair cannot be 0!");
        uniswapV2Pair = _pair;
        emit PairUpdated(_pair);
    }

    // Transfer and tax logic
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "Cannot transfer to 0");
        require(to != address(0), "Cannot transfer from 0");
        require(balanceOf(from) >= amount, "Amount exceeds balance");

        // Whitelisted addresses
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            super._transfer(from, to, amount);
            return;
        }

        require(publicTradingActive, "Trading not active");

        // If coming from or going to uniswap pair
        if (
            (from == uniswapV2Pair || to == uniswapV2Pair) && !inSwapAndLiquify
        ) {
            // If token sale, swap taxed tokens stored in this contract 
            // for eth, then send to marketing wallet and add liquidity
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

            require(amount <= maxTxAmount, "Max transaction amount exceeded");

            // If token purchase, check max wallet amount
            if (from == uniswapV2Pair) {
                require(
                    (amount + balanceOf(to)) <= maxWalletAmount,
                    "Max wallet amount exceeded"
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

            // Calculate taxes
            uint256 marketingShare = ((amount * taxForMarketing) / 100);
            uint256 liquidityShare = ((amount * taxForLiquidity) / 100);
            uint256 transferAmount = amount - (marketingShare + liquidityShare);

            // Transfer tax amount to this contract
            super._transfer(
                from,
                address(this),
                (marketingShare + liquidityShare)
            );

            // Update marketing reserves with marketing tax
            // portion of tokens transferred to this contract
            _marketingReserves += marketingShare;

            // Transfer remaining non-taxed amount
            super._transfer(from, to, transferAmount);
        } else {
            super._transfer(from, to, amount);
        }
    }

    // Enable public trading
    function enablePublicTrading() external onlyOwner {
        publicTradingActive = true;
        emit PublicTradingStarted();
    }

    // Exclude address from fee
    function excludeFromFee(address _address, bool _status) external onlyOwner {
        _isExcludedFromFee[_address] = _status;
        emit ExcludedFromFeeUpdated(_address, _status);
    }

    // Swap tokens and add liquidiy to uniswap pair
    function _swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        uint256 half = contractTokenBalance >> 1;
        uint256 otherHalf = (contractTokenBalance - half);

        uint256 initialBalance = address(this).balance;

        _swapTokensForEth(half);

        uint256 newBalance = (address(this).balance - initialBalance);

        _addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    // Swap tokens for eth using the uniswap pair
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

    // Add liquidiy to uniswap pair
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

    // Change wallet marketing taxes are sent to
    function changeMarketingWallet(
        address newWallet
    ) external onlyOwner returns (bool) {
        require(newWallet != DEAD, "LP Pair cannot be DEAD");
        require(newWallet != address(0), "LP Pair cannot be 0");
        marketingWallet = newWallet;

        emit MarketingWalletUpdated(newWallet);
        return true;
    }

    // Update tax amounts
    function changeTaxForLiquidityAndMarketing(
        uint256 _taxForLiquidity,
        uint256 _buyTaxForMarketing,
        uint256 _sellTaxForMarketing
    ) external onlyOwner returns (bool) {
        require(
            (_taxForLiquidity + _buyTaxForMarketing) < 11,
            "Max tax is 10%"
        );
        require(
            (_taxForLiquidity + _sellTaxForMarketing) < 11,
            "Max tax is 10%"
        );
        taxForLiquidity = _taxForLiquidity;
        buyTaxForMarketing = _buyTaxForMarketing;
        sellTaxForMarketing = _sellTaxForMarketing;

        emit TaxUpdated(
            _taxForLiquidity,
            _buyTaxForMarketing,
            _sellTaxForMarketing
        );
        return true;
    }

    // Update thresholds for when tax token
    // reserves should be swapped for eth
    function changeSwapThresholds(
        uint256 _numTokensSellToAddToLiquidity,
        uint256 _numTokensSellToAddToETH
    ) external onlyOwner returns (bool) {
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

        emit SwapThresholdUpdated(
            _numTokensSellToAddToLiquidity,
            _numTokensSellToAddToETH
        );
        return true;
    }

    // Update the max transaction amount
    function changeMaxTxAmount(
        uint256 _maxTxAmount
    ) external onlyOwner returns (bool) {
        maxTxAmount = _maxTxAmount;

        emit MaxTransactionAmountUpdated(_maxTxAmount);
        return true;
    }

    // Update the max tokens stored in a single wallet
    function changeMaxWalletAmount(
        uint256 _maxWalletAmount
    ) external onlyOwner returns (bool) {
        maxWalletAmount = _maxWalletAmount;

        emit MaxWalletAmountUpdated(_maxWalletAmount);
        return true;
    }
}
