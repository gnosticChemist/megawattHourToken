// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FunctionsRequest} from "@chainlink/contracts@1.1.0/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {FunctionsClient} from "@chainlink/contracts@1.1.0/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract SmartGrid is ConfirmedOwner, FunctionsClient, ERC20{
    using Strings for uint256;
    using FunctionsRequest for FunctionsRequest.Request;

    struct Producer{
        uint256 deviceId;
        uint256 energyProduced;
    }
    mapping (address wallet => Producer producer) private producers;

    address router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0; //Sepolia Router
    constructor(uint64 subId)
        FunctionsClient(router)
        ConfirmedOwner(msg.sender)
        ERC20("MegaWattHour", "MWh")
    {
        i_subId = subId;
    }

    function register(address walletProducer, uint256 deviceId) public onlyOwner{
        producers[walletProducer] = Producer(deviceId, 0);
    }

    function register(address walletProducer, uint256 deviceId, uint256 startingValue) public onlyOwner{
        producers[walletProducer] = Producer(deviceId, startingValue);
    }

    function mintRequest(address to) public{
        require(producers[to].deviceId != 0);
        sendRequest(producers[to].deviceId);
    }

    string source = 
    "const apiResponse = await Functions.makeHttpRequest({"
            "url: `https://netzer0.app.br/api/v1/integrations/http/e2a81c53-e661-1b96-53eb-4d64ce520e8f`,"
            "method: 'POST',"
            "headers: {"
            "accept: 'application/json',"
        "},"
        "data: { deviceId: args[0], deviceType: 'DEVICE'}});"
    "if (apiResponse.error) {"
    "throw Error('Request failed');"
    "}"
    "const { data } = apiResponse;"
    "var value = parseInt(data.Exportacao.value);"
    "return Functions.encodeUint256(value);";

    bytes32 constant DON_ID = hex"66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000";
    uint32 constant GAS_LIMIT = 300000;
    uint64 immutable i_subId;
    mapping(bytes32 requestId => address target) private s_requests;

    function sendRequest(
        uint256 deviceId
    ) internal returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source); // Initialize the request with JS code
        string[] memory args = new string[](1);
        args[0] = deviceId.toString();
        req.setArgs(args); // Set the arguments for the request

        // Send the request and store the request ID
        bytes32 reqId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requests[reqId] = msg.sender;

        return reqId;
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory /*err*/) internal override{
        address target = s_requests[requestId];
        uint256 produced = uint256(bytes32(response));
        if(produced > producers[target].energyProduced){
            _mint(target, produced - producers[target].energyProduced);
            producers[target].energyProduced = produced;
        }
    }

    function decimals() public view virtual override returns (uint8) {
        return 3;
    }

    function getProduced(address wallet) public view returns(uint256){
        return producers[wallet].energyProduced;
    }
}