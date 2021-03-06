pragma solidity ^ 0.4.25;

contract TRC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function allowance(address owner, address spender) external view returns (uint);

    function transfer(address to, uint value) external returns (bool);

    function approve(address spender, uint value) external returns (bool);
    
    function decimals() external returns (uint);

    function transferFrom(address from, address to, uint value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint value);

    event Approval(address indexed owner, address indexed spender, uint value);
}


contract LuckyHash {
    using SafeMath for uint256;
    
    event Lottory(address indexed user, uint256 term, uint256 start, uint256 end);
    event Draw(address indexed winner, uint256 rank, uint256 number, uint256 prize, uint256 block, uint256 term);
    event Finish(address indexed user, uint256 money, uint256 term);
    event Start(address indexed user, uint256 term);

    address owner;
    address developer;
    address marketing;
    address public poolAddr;
    address public tokenAddr;
    uint256 public tokenDecimal;

    struct Receipt {
        uint256 start;
        uint256 end;
    }

    struct Term {
        uint256 startBlock;
        uint256 endBlock;
        uint256 drawBlock;
        
        uint256 totalReward;
        uint256 maxNumber;
        
        address endUser;
        address drawUser;
        
        address[] first10User;

        uint256[] sellIdx;
        address[] winer;
        uint256[] winNumber;
        uint256[] calcBlock;
        uint256[] prize;

        mapping(address => Receipt[]) userNumbers;
        mapping(uint256 => address) number2User;
    }

    enum State {
        Ongoing,
        Pending,
        Finished
    }
    State public state;
    
    uint256 public playCnt;
    uint256 public totalReceive;

    uint256 public currentTerm;
    mapping(uint256 => Term) public terms_;

    uint256 public number_;
    uint256 public totalReward_;
    uint256 public maxReward_;
    
    uint256 public startBlock_;
    uint256 public endBlock_;
    uint256 public startTime_;
    uint256 public endTime_;

    uint256 constant SUN = 1000000;
    uint256 constant PRICE = 100 * SUN;
    uint256 constant MIN_REWARD = 1000 * PRICE; // 100000
    uint256 constant MAX_REWARD = 10000 * PRICE; // 1000000
    uint256 constant MAX_TIME = 60*60*2; // two hour
    uint256 constant DRAW_START_GAP = 80; //100 * 3 = 300 / 60 = 5 minute
    uint256 constant DRAW_BLOCK_CNT = 15;
    
    uint256[] DRAW_BLOCK_GAP;
    uint256[] PRIZE_RATE;
    uint256 constant POOL_RATE = 10;
    uint256 constant DEVELOPER_RATE = 6;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier finished() {
        require(state == State.Finished, "not finished!!!");
        _;
    }

    modifier started() {
        require(state == State.Ongoing, "not start yet");
        _;
    }

    modifier pending() {
        require(state == State.Pending, "not finished yet");
        _;
    }
    
    function __sendToken(address _to, uint256 _val) internal returns (bool) {
        if (TRC20(tokenAddr).balanceOf(owner) >= _val && TRC20(tokenAddr).allowance(owner, address(this)) >= _val) {
            if (TRC20(tokenAddr).transferFrom(owner, address(this), _val)) {
                return TRC20(tokenAddr).transfer(_to, _val);
            }
        }
        return false;
    }

    constructor(address _tokenAddr) public {
        owner = msg.sender;
        developer = msg.sender;
        marketing = msg.sender;
        poolAddr = msg.sender;

        tokenAddr = _tokenAddr;
        tokenDecimal = 10 ** TRC20(tokenAddr).decimals();
        
        DRAW_BLOCK_GAP.push(15);
        DRAW_BLOCK_GAP.push(25);
        DRAW_BLOCK_GAP.push(35);
        
        PRIZE_RATE.push(50);
        PRIZE_RATE.push(20);
        PRIZE_RATE.push(10);

        state = State.Finished;
    }
    
    function setPool(address _addr) public onlyOwner {
        poolAddr = _addr;
    }
    
    function setDeveloper(address _addr) public onlyOwner {
        require(address(0) != _addr);
        developer = _addr;
    }

    function setMarketing(address _addr) public onlyOwner {
        require(address(0) != _addr);
        marketing = _addr;
    }
    
    function balance() public view returns(uint256) {
        return address(this).balance;
    }
    
    function() public payable {
        if (state == State.Finished) {
            start();
            return;
        }
        if (state == State.Ongoing) {
            if (!__finish()) {
                buy();
            }
            return;
        }
        if (state == State.Pending) {
            draw();
        }
    }

    function start() public payable {
        require(msg.value == 0);
        __start();
    }
    
    function __start() internal finished {
        if (totalReward_ <= MIN_REWARD) {
            maxReward_ = MIN_REWARD;
        } else {
            maxReward_ = totalReward_.div(endTime_-startTime_).mul(MIN_REWARD);
            if (maxReward_ > MAX_REWARD) {
                maxReward_ = MAX_REWARD;
            }
            if (maxReward_ < MIN_REWARD) {
                maxReward_ = MIN_REWARD;
            }
        }

        currentTerm++;
        startTime_ = now;
        startBlock_ = block.number;
        endTime_ = 0;
        endBlock_ = 0;
        number_ = 0;
        totalReward_ = 0;

        Term memory term;
        term.startBlock = block.number;
        terms_[currentTerm] = term;

        state = State.Ongoing;
        
        emit Start(msg.sender, currentTerm);
    }
    
    function end() public payable started {
        require(msg.value == 0);
        if (__finish()) {
            return;
        }
        revert();
    }
    
    function __finish() internal started returns (bool) {
        if (totalReward_ >= maxReward_ || now >= startTime_ + MAX_TIME) {
            state = State.Pending;
            
            Term storage term = terms_[currentTerm];
            term.endUser = msg.sender;
            term.endBlock = block.number;
            term.totalReward = totalReward_;
            endTime_ = now;
            endBlock_ = block.number;
            
            emit Finish(msg.sender, totalReward_, currentTerm);
            return true;
        }
        return false;
    }

    function buy() public payable started returns(uint256, uint256) {
        require(totalReward_ < maxReward_);
        require(msg.value >= PRICE, "not sufficient fee!");

        uint256 nums = msg.value.div(PRICE);
        uint256 amount = PRICE.mul(nums);
        uint256 change = msg.value.sub(amount);

        uint256 endNumber = number_ + nums - 1;

        Term storage term = terms_[currentTerm];

        term.number2User[number_] = msg.sender;
        term.userNumbers[msg.sender].push(Receipt(number_, endNumber));
        term.sellIdx.push(number_);
        
        if (change > 0) {
            msg.sender.transfer(change);
        }
        
        if (number_ < 10) {
            uint256 off = 10 - number_;
            if (off >= nums) {
                off = nums;
            }
            for (uint256 i = 0; i < off; i++) {
                term.first10User.push(msg.sender);
            }
        }
        
        __sendToken(msg.sender, nums.mul(tokenDecimal));
        
        number_ += nums;
        term.maxNumber = number_;
        totalReward_ = totalReward_.add(amount);
        
        playCnt++;
        totalReceive = totalReceive.add(msg.value);
        
        emit Lottory(msg.sender, currentTerm, number_-nums, endNumber);
        
        __finish();
        
        return (number_ - nums, nums);
    }

    function draw() public payable pending {
        require(block.number >= endBlock_ + DRAW_START_GAP, "waiting......");
        
        if (totalReward_ == 0) {
            state = State.Finished;
            __start();
            return;
        }
        
        if (block.number - (endBlock_ + DRAW_BLOCK_GAP[0]) > 250) {
            endBlock_ = block.number - DRAW_START_GAP;
        }

        Term storage term = terms_[currentTerm];
        term.drawUser = msg.sender;
        term.drawBlock = block.number;
        term.totalReward = totalReward_;
        
        uint256 change = totalReward_;
        uint256 calcBlock;
        uint256 reward;
        for (uint8 i = 0; i < 3; i++) {
            calcBlock = endBlock_+DRAW_BLOCK_GAP[i];
            term.calcBlock.push(calcBlock);
            
            term.winNumber.push(__drawNumber(calcBlock, DRAW_BLOCK_CNT, number_));
            term.winer.push(__getOwner(term.winNumber[i], currentTerm));
            
            reward = totalReward_.mul(PRIZE_RATE[i]).div(100);
            term.winer[i].transfer(reward);
            term.prize.push(reward);
            change = change.sub(reward);
            
            emit Draw(term.winer[i], i+1, term.winNumber[i], reward, calcBlock, currentTerm);
        }

        poolAddr.transfer(totalReward_.mul(POOL_RATE).div(100));
        change = change.sub(totalReward_.mul(POOL_RATE).div(100));
        developer.transfer(totalReward_.mul(DEVELOPER_RATE).div(100));
        change == change.sub(totalReward_.mul(POOL_RATE).div(100));
        
        if (change > PRICE) {
            term.drawUser.transfer(PRICE);
            change = change.sub(PRICE);
        }
        
        if (change > PRICE) {
            term.endUser.transfer(PRICE);
            change = change.sub(PRICE);
        }
        
        reward = PRICE.mul(20).div(100);
        if (change > reward.mul(term.first10User.length)) {
            for (i = 0; i < term.first10User.length; i++) {
                term.first10User[i].transfer(reward);
            }
            change = change.sub(reward.mul(term.first10User.length));
        }
        
        marketing.transfer(address(this).balance);

        state = State.Finished;
        __start();
    }

    function __drawNumber(uint256 _start, uint256 _cnt, uint256 _range) internal view returns(uint256 ret) {
        for (uint256 i = 0; i < _cnt; i++) {
            ret += uint256(keccak256(abi.encodePacked(blockhash(_start + i))));
        }
        ret = ret % _range;
        return ret;
    }

    function __getOwner(uint256 _number, uint256 _term) internal view returns (address) {
        Term storage term = terms_[_term];

        uint256 mid;
        uint256 left = 0;
        uint256 right = term.sellIdx.length - 1;

        while (left <= right) {
            mid = left.add(right).div(2);

            if (term.sellIdx[mid] > _number) {
                right = mid.sub(1);
                continue;
            }
            if (term.sellIdx[mid] == _number) {
                break;
            }
            if (term.sellIdx[mid] < _number) {
                if (mid + 1 >= term.sellIdx.length) {
                    break;
                }
                if (term.sellIdx[mid + 1] > _number) {
                    break;
                }
                left = mid.add(1);
            }
        }

        uint256 number = term.sellIdx[mid];
        return term.number2User[number];
    }

    function getTermNumberOwner(uint256 _number, uint256 _term) public view returns(address) {
        require(_term <= currentTerm && _term > 0);

        Term storage term = terms_[_term];
        require(_number < term.maxNumber);
        
        return __getOwner(_number, _term);
    }

    function getTermUserNumbers(address _addr, uint256 _term) public view returns(uint256[] memory, uint256[] memory) {
        require(_term <= currentTerm && _term > 0);

        if (msg.sender != _addr) {
            require(msg.sender == owner, "invalid operation");
        }

        if (_term == 0) {
            _term = currentTerm;
        }

        Term storage term = terms_[_term];

        require(term.userNumbers[_addr].length > 0, "invalid player");

        uint256[] memory starts = new uint256[](term.userNumbers[_addr].length);
        uint256[] memory ends = new uint256[](term.userNumbers[_addr].length);

        for (uint256 i = 0; i < term.userNumbers[_addr].length; i++) {
            starts[i] = term.userNumbers[_addr][i].start;
            ends[i] = term.userNumbers[_addr][i].end;
        }
        return (starts, ends);
    }
    
    function getTermResult(uint256 _term) public view returns (uint256[], address[], uint256[] memory, address[] memory, uint256[] memory) {
        require(_term > 0 && _term <= currentTerm);
        
        Term storage term = terms_[_term];
        uint256[] memory data = new uint256[](5+term.calcBlock.length);
        data[0] = term.startBlock;
        data[1] = term.endBlock;
        data[2] = term.drawBlock;
        data[3] = term.totalReward;
        data[4] = term.maxNumber;
        
        for (uint256 i = 0; i < term.calcBlock.length; i++) {
            data[5+i] = term.calcBlock[i];
        }    
        
        address[]memory data1 = new address[](2 + term.first10User.length);
        data1[0] = term.endUser;
        data1[1] = term.drawUser;
        for (i = 0; i < term.first10User.length; i++) {
            data1[2+i] = term.first10User[i];
        }
        
        uint256[] memory winNumber = new uint256[](term.winNumber.length);
        address[] memory winer = new address[](term.winer.length);
        uint256[] memory prize = new uint256[](term.prize.length);
        
        for (i = 0; i < term.winNumber.length; i++) {
            winNumber[i] = term.winNumber[i];
            winer[i] = term.winer[i];
            prize[i] = term.prize[i];
        }
        
        return (
            data,
            data1,
            winNumber,
            winer,
            prize
        );
    }

    function checkin() public payable {}
}

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns(uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns(uint256) {
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns(uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns(uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}
