pragma solidity 0.6.12;


                                                                                                                                                                                                                    
//----------------------------------------------------------------------------------
//    I n s t a n t
//
//        .:mmm.         .:mmm:.       .ii.  .:SSSSSSSSSSSSS.     .oOOOOOOOOOOOo.  
//      .mMM'':Mm.     .:MM'':Mm:.     .II:  :SSs..........     .oOO'''''''''''OOo.
//    .:Mm'   ':Mm.   .:Mm'   'MM:.    .II:  'sSSSSSSSSSSSSS:.  :OO.           .OO:
//  .'mMm'     ':MM:.:MMm'     ':MM:.  .II:  .:...........:SS.  'OOo:.........:oOO'
//  'mMm'        ':MMmm'         'mMm:  II:  'sSSSSSSSSSSSSS'     'oOOOOOOOOOOOO'  
//
//----------------------------------------------------------------------------------

import "./Utils/CloneFactory.sol";
import "../interfaces/IMisoFarm.sol";
import "./Access/MISOAccessControls.sol";

contract MISOFarmFactory is CloneFactory {

    /// @notice Responsible for access rights to the contract.
    MISOAccessControls public accessControls;

    /// @notice Whether farm factory has been initialized or not.
    bool private initialised;

    /// @notice Struct to track Farm template.
    struct Farm {
        bool exists;
        uint256 templateId;
        uint256 index;
    }

    /// @notice Mapping from auction created through this contract to Auction struct.
    mapping(address => Farm) public farmInfo;

    /// @notice Farms created using the factory.
    address[] public farms;

    /// @notice Template id to track respective farm template.
    uint256 public farmTemplateId;

    /// @notice Mapping from template id to farm template address.
    mapping(uint256 => address) private farmTemplates;

    /// @notice mapping from farm template address to farm template id
    mapping(address => uint256) private farmTemplateToId;

    /// @notice Minimum fee to create a farm through the factory.
    uint256 public minimumFee;
    uint256 public integratorFeePct;

    /// @notice Any MISO dividends collected are sent here.
    address payable public misoDiv;

    /// @notice Event emitted when first initializing the Miso Farm Factory.
    event MisoInitFarmFactory(address sender);

    /// @notice Event emitted when a farm is created using template id.
    event FarmCreated(address indexed owner, address indexed addr, address farmTemplate);

    /// @notice Event emitted when farm template is added to factory.
    event FarmTemplateAdded(address newFarm, uint256 templateId);

    /// @notice Event emitted when farm template is removed.
    event FarmTemplateRemoved(address farm, uint256 templateId);

    /**
     * @notice Single gateway to initialize the MISO Farm factory with proper address.
     * @dev Can only be initialized once
     * @param _accessControls Sets address to get the access controls from.
     * @param _misoDiv Sets address to send the dividends.
     * @param _minimumFee Sets a minimum fee for creating farm in the factory.
     * @param _integratorFeePct Fee to UI integration
     */
    function initMISOFarmFactory(
        address _accessControls,
        address payable _misoDiv,
        uint256 _minimumFee,
        uint256 _integratorFeePct
    )
        external
    {
        /// @dev Maybe missing require message?
        require(!initialised);
        require(_misoDiv != address(0));
        initialised = true;
        misoDiv = _misoDiv;
        minimumFee = _minimumFee;
        integratorFeePct = _integratorFeePct;
        accessControls = MISOAccessControls(_accessControls);
        emit MisoInitFarmFactory(msg.sender);
    }

    /**
     * @notice Sets the minimum fee.
     * @param _amount Fee amount.
     */
    function setMinimumFee(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "MISOFarmFactory: Sender must be operator"
        );
        minimumFee = _amount;
    }

    /**
     * @notice Sets integrator fee percentage.
     * @param _amount Percentage amount.
     */
    function setIntegratorFeePct(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "MISOFarmFactory: Sender must be operator"
        );
        /// @dev this is out of 1000, ie 25% = 250
        require(
            _amount <= 1000, 
            "MISOFarmFactory: Range is from 0 to 1000"
        );
        integratorFeePct = _amount;
    }

    /**
     * @notice Sets dividend address.
     * @param _divaddr Dividend address.
     */
    function setDividends(address payable _divaddr) external  {
        require(
            accessControls.hasAdminRole(msg.sender),
            "MISOFarmFactory: Sender must be operator"
        );
        require(_divaddr != address(0));
        misoDiv = _divaddr;
    }

    /**
     * @notice Deploys a farm corresponding to the _templateId and transfers fees.
     * @param _templateId Template id of the farm to create.
     * @param _integratorFeeAccount Address to pay the fee to.
     * @return farm address.
     */
    function deployFarm(
        uint256 _templateId,
        address payable _integratorFeeAccount
    )
        public payable returns (address farm)
    {
        require(msg.value >= minimumFee, "MISOFarmFactory: Failed to transfer minimumFee");
        require(farmTemplates[_templateId] != address(0));
        uint256 integratorFee = 0;
        uint256 misoFee = msg.value;
        if (_integratorFeeAccount != address(0) && _integratorFeeAccount != misoDiv) {
            integratorFee = misoFee * integratorFeePct / 1000;
            misoFee = misoFee - integratorFee;
        }
        farm = createClone(farmTemplates[_templateId]);
        farmInfo[address(farm)] = Farm(true, _templateId, farms.length);
        farms.push(address(farm));
        emit FarmCreated(msg.sender, address(farm), farmTemplates[_templateId]);
        if (misoFee > 0) {
            misoDiv.transfer(misoFee);
        }
        if (integratorFee > 0) {
            _integratorFeeAccount.transfer(integratorFee);
        }
    }

    /**
     * @notice Creates a farm corresponding to the _templateId.
     * @dev Initializes farm with the parameters passed.
     * @param _templateId Template id of the farm to create.
     * @param _integratorFeeAccount Address to pay the fee to.
     * @param _data Data to be passed to the farm contract for init.
     * @return farm address.
     */
    function createFarm(
        uint256 _templateId,
        address payable _integratorFeeAccount,
        bytes calldata _data
    )
        external payable returns (address farm)
    {
        farm = deployFarm(_templateId, _integratorFeeAccount);
        IMisoFarm(farm).initFarm(_data);
    }

    /**
     * @notice Function to add a farm template to create through factory.
     * @dev Should have operator access.
     * @param _template Farm template address to create a farm.
     */
    function addFarmTemplate(address _template) external {
        require(
            accessControls.hasOperatorRole(msg.sender),
            "MISOFarmFactory: Sender must be operator"
        );
        require(farmTemplateToId[_template] == 0);
        farmTemplateId++;
        farmTemplates[farmTemplateId] = _template;
        farmTemplateToId[_template] = farmTemplateId;
        emit FarmTemplateAdded(_template, farmTemplateId);
    }

     /**
     * @notice Function to remove a farm template.
     * @dev Should have operator access.
     * @param _templateId Refers to template ID that is to be deleted.
     */
    function removeFarmTemplate(uint256 _templateId) external {
        require(
            accessControls.hasOperatorRole(msg.sender),
            "MISOFarmFactory: Sender must be operator"
        );
        require(farmTemplates[_templateId] != address(0));
        address template = farmTemplates[_templateId];
        farmTemplates[_templateId] = address(0);
        delete farmTemplateToId[template];
        emit FarmTemplateRemoved(template, _templateId);
    }

    /**
     * @notice Get the address based on template ID.
     * @param _farmTemplate Farm template ID.
     * @return Address of the required template ID.
     */
    function getFarmTemplate(uint256 _farmTemplate) external view returns (address) {
        return farmTemplates[_farmTemplate];
    }

    /**
     * @notice Get the ID based on template address.
     * @param _farmTemplate Farm template address.
     * @return ID of the required template address.
     */
    function getTemplateId(address _farmTemplate) external view returns (uint256) {
        return farmTemplateToId[_farmTemplate];
    }

    /**
     * @notice Get the total number of farms in the factory.
     * @return Farms count.
     */
    function numberOfFarms() external view returns (uint256) {
        return farms.length;
    }

    /**
     * @notice Get all farm created in the factory.
     * @return created farms.
     */
    function getFarms() external view returns(address[] memory) {
        return farms;
    }
}
