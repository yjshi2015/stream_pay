
## call createAndDeposit  alice
sui client call --function createAndDeposit --package 0x9eb2648c160c70854b39d1b1d9e828b0f918efe2daf798d9fd936b9d075bc5e1 --module liner_pay --args 0x00bc6a9bfa84153db2d5113c10329e6fcd5c9617b83db81364d56d0096b7ce95

Transaction Digest: 412CKyt8foCk9uDC1vRnd6jtrs2WKda3Vbfp7p3MpBWY

## call createStream of bob (0.1 SUI/s)
sui client call --function createStream --package 0x9eb2648c160c70854b39d1b1d9e828b0f918efe2daf798d9fd936b9d075bc5e1 --module liner_pay --args 0x8dbfeb48a0f8c0d55ef6daf75e08b2f3a54ce3d294812bad49f7987bf7e8485d 0xc4301a727914c051c987331f30d002ef907f6f6e4badfec8981e6275ed22486c 100000000 0x6

Transaction Digest: 86K8p1T8nGsiu6aYMae1bo1gA7AHVTMczhciFjKRZhT5

## call withdraw of bob
sui client switch --address xxxx

sui client call --function withdraw --package 0x9eb2648c160c70854b39d1b1d9e828b0f918efe2daf798d9fd936b9d075bc5e1 --module liner_pay --args 0x8dbfeb48a0f8c0d55ef6daf75e08b2f3a54ce3d294812bad49f7987bf7e8485d 0xd9b611abf4a3fcc40c661abce42ecb982a060673b28a8d66c51244ad29b06006 100000000 0x6

Transaction Digest: 8PJNFNTWpqK8oPUXwoHWmEaZ2MnDy7NtBWosebNYe1Gh

## call getPayerBalance
sui client call --function getPayerBalance --package 0x9eb2648c160c70854b39d1b1d9e828b0f918efe2daf798d9fd936b9d075bc5e1 --module liner_pay --args 0x8dbfeb48a0f8c0d55ef6daf75e08b2f3a54ce3d294812bad49f7987bf7e8485d 0x6

### not ok
sui client ptb --move-call 0x9eb2648c160c70854b39d1b1d9e828b0f918efe2daf798d9fd936b9d075bc5e1::liner_pay::getPayerBalance @0x8dbfeb48a0f8c0d55ef6daf75e08b2f3a54ce3d294812bad49f7987bf7e8485d @0x6 --assign bal


## call withdrawPayerAll
sui client call --function withdrawPayerAll --package 0x9eb2648c160c70854b39d1b1d9e828b0f918efe2daf798d9fd936b9d075bc5e1 --module liner_pay --args 0x8dbfeb48a0f8c0d55ef6daf75e08b2f3a54ce3d294812bad49f7987bf7e8485d 0x6