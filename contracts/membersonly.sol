// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

abstract contract MembersOnly {
    /*************
     * Modifiers *
     *************/
    modifier onlyOwner() {
        require(msg.sender == owner, "E0");
        _;
    }

    modifier onlyAuthorizedUser() {
        require(_authorizedUsers[msg.sender], "No auth.");
        _;
    }

    /**************
     * Properties *
     **************/
    address immutable public owner;

    /******************
     * Private Fields *
     ******************/
    mapping(address user => bool isAuthorized) private _authorizedUsers;

    constructor() {
        owner = msg.sender;
    }

    /// @notice Adds an authorized user to the contract.
    function addAuthorizedUser(address user) external onlyOwner {
        _authorizedUsers[user] = true;
    }

    /// @notice Checks if a user is authorized.
    function isAuthorized() public view returns (bool) {
        return isAuthorized(msg.sender);
    }

    /// @notice Checks if a user is authorized.
    /// @param user The address of the user to check.
    function isAuthorized(address user) internal view returns (bool) {
        return _authorizedUsers[user];
    }
}