// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./FundManager.sol";
import "../common/uniswap/IUniswapV2Router02.sol";
import "../common/uniswap/IWETH.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";



contract FiberRouter is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address public pool;

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }


    /**
     @notice The payable receive method
     */
    receive() external payable {
    }



    /**
     @notice Sets the fund manager contract.
     @param _pool The fund manager
     */
    function setPool(address _pool) external onlyOwner {
        pool = _pool;
    }



    /*
     @notice Initiate an x-chain swap.
     @param token The source token to be swaped
     @param amount The source amount
     @param targetNetwork The chain ID for the target network
     @param targetToken The target token address
     @param swapTargetTokenTo Swap the target token to a new token
     @param targetAddress Final destination on target
     */
    function swap(
        address token,
        uint256 amount,
        uint256 targetNetwork,
        address targetToken,
        address targetAddress
    ) external {
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, pool, amount);
        FundManager(pool).swapToAddress(
            token,
            amount,
            targetNetwork,
            targetToken,
            targetAddress
        );
    }

    /*
     @notice Do a local swap and generate a cross-chain swap
     @param swapRouter The local swap router
     @param amountIn The amount in
     @param amountCrossMin Equivalent to amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap dealine
     @param crossTargetNetwork The target network for the swap
     @param crossSwapTargetTokenTo If different than crossTargetToken, a swap
       will also be required on the other end
     @param crossTargetAddress The target address for the swap
     */
    function swapAndCross(
        address swapRouter,
        uint256 amountIn,
        uint256 amountCrossMin, // amountOutMin on uniswap
        address[] calldata path,
        uint256 deadline,
        uint256 crossTargetNetwork,
        address crossTargetToken
    ) external nonReentrant {
        amountIn = SafeAmount.safeTransferFrom(path[0], msg.sender, address(this), amountIn);
        IERC20Upgradeable(path[0]).approve(swapRouter, amountIn);
        _swapAndCross(
            msg.sender,
            swapRouter,
            amountIn,
            amountCrossMin,
            path,
            deadline,
            crossTargetNetwork,
            crossTargetToken
            // crossSwapTargetTokenTo
            // crossTargetAddress
        );
    }


    /*
     @notice Do a local swap and generate a cross-chain swap
     @param swapRouter The local swap router
     @param amountCrossMin Equivalent to amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap dealine
     @param crossTargetNetwork The target network for the swap
     @param crossSwapTargetTokenTo If different than crossTargetToken, a swap
       will also be required on the other end
     @param crossTargetAddress The target address for the swap
     */
    function swapAndCrossETH(
        address swapRouter,
        uint256 amountCrossMin, // amountOutMin
        address[] calldata path,
        uint256 deadline,
        uint256 crossTargetNetwork,
        address crossTargetToken
    ) external payable {
        uint256 amountIn = msg.value;
        address weth = IUniswapV2Router01(swapRouter).WETH();
        // approveIfRequired(weth, swapRouter, amountIn);
        IERC20Upgradeable(weth).approve(swapRouter, amountIn);
        IWETH(weth).deposit{value: amountIn}();
        _swapAndCross(
            msg.sender,
            swapRouter,
            amountIn,
            amountCrossMin,
            path,
            deadline,
            crossTargetNetwork,
            crossTargetToken
            // crossSwapTargetTokenTo
            // crossTargetAddress
        );
    }


    /*
    @notice Runs a local swap and then a cross chain swap
    @param to The receiver
    @param swapRouter the swap router
    @param amountIn The amount in
    @param amountCrossMin Equivalent to amountOutMin on uniswap 
    @param path The swap path
    @param deadline The swap deadline
    @param crossTargetNetwork The target chain ID
    @param crossTargetToken The target network token
    @param crossSwapTargetTokenTo The target network token after swap
    @param crossTargetAddress The receiver of tokens on the target network
    */
    function _swapAndCross(
        address to,
        address swapRouter,
        uint256 amountIn,
        uint256 amountCrossMin, 
        address[] calldata path,
        uint256 deadline,
        uint256 crossTargetNetwork,
        address crossTargetToken
        // address crossSwapTargetTokenTo
        // address crossTargetAddress
    ) internal {
        IUniswapV2Router02(swapRouter)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountCrossMin,
                path,
                address(this),
                deadline
            );
        address crossToken = path[path.length - 1];
        IERC20Upgradeable(crossToken).approve(pool, amountCrossMin);
        FundManager(pool).swapToAddress(
            crossToken,
            amountCrossMin,
            crossTargetNetwork,
            crossTargetToken,
            to
        );
    }



    /*
     @notice Withdraws funds based on a multisig
     @dev For signature swapToToken must be the same as token
     @param token The token to withdraw
     @param payee Address for where to send the tokens to
     @param amount The mount
     @param sourceChainId The source chain initiating the tx
     @param swapTxId The txId for the swap from the source chain
     @param multiSignature The multisig validator signature
     */
    function withdrawSigned(
        address token,
        address payee,
        uint256 amount,
        bytes32 salt,
        bytes memory multiSignature
    ) external {
        FundManager(pool).withdrawSigned(
            token,
            payee,
            amount,
            salt,
            multiSignature
        );
    }

    function withdraw(
        address token,
        address payee,
        uint256 amount
    ) external {
        FundManager(pool).withdraw(
            token,
            payee,
            amount
        );
    }


    /*
     @notice Withdraws funds and swaps to a new token
     @param to Address for where to send the tokens to
     @param swapRouter The swap router address
     @param amountIn The amount to swap
     @param sourceChainId The source chain Id. Used for signature
     @param swapTxId The source tx Id. Used for signature
     @param amountOutMin Same as amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap deadline
     @param multiSignature The multisig validator signature
     */
    function withdrawSignedAndSwap(
        address to,
        address swapRouter,
        uint256 amountIn,
        uint256 amountOutMin, // amountOutMin on uniswap
        address[] calldata path,
        uint256 deadline,
        bytes32 salt,
        bytes memory multiSignature
    ) external {
        require(path.length > 1, "BR: path too short");
        FundManager(pool).withdrawSigned(
            path[0],
            address(this),
            amountIn,
            salt,
            multiSignature
        );
        amountIn = IERC20Upgradeable(path[0]).balanceOf(address(this)); // Actual amount received
        IERC20Upgradeable(path[0]).approve(swapRouter, amountIn);
        IUniswapV2Router02(swapRouter)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }


    /*
     @notice Withdraws funds and swaps to a new token
     @param to Address for where to send the tokens to
     @param swapRouter The swap router address
     @param amountIn The amount to swap
     @param amountOutMin Same as amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap deadline
     @param multiSignature The multisig validator signature
     */
    function withdrawAndSwap(
        address to,
        address swapRouter,
        uint256 amountIn,
        uint256 amountOutMin, // amountOutMin on uniswap
        address[] calldata path,
        uint256 deadline
    ) external {
        require(path.length > 1, "BR: path too short");
        FundManager(pool).withdraw(
            path[0],
            address(this),
            amountIn
        );
        amountIn = IERC20Upgradeable(path[0]).balanceOf(address(this)); // Actual amount received
        IERC20Upgradeable(path[0]).approve(swapRouter, amountIn);
        IUniswapV2Router02(swapRouter)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }

    /*
     @notice Withdraws funds and swaps to a new token
     @param to Address for where to send the tokens to
     @param swapRouter The swap router address
     @param amountIn The amount to swap
     @param sourceChainId The source chain Id. Used for signature
     @param swapTxId The source tx Id. Used for signature
     @param amountOutMin Same as amountOutMin on uniswap
     @param path The swap path
     @param deadline The swap deadline
     @param multiSignature The multisig validator signature
     */
    function withdrawSignedAndSwapETH(
        address to,
        address swapRouter,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline,
        bytes32 salt,
        bytes memory multiSignature
    ) external {
        FundManager(pool).withdrawSigned(
            path[0],
            address(this),
            amountIn,
            salt,
            multiSignature
        );
        amountIn = IERC20Upgradeable(path[0]).balanceOf(address(this)); // Actual amount received
        IUniswapV2Router02(swapRouter)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }

}