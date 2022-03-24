var sha512 = require('js-sha512');

// spit out just a sha512 hash of whatever comes in the door
// console.log(sha512(process.argv.slice(2)[0]))

// const myArgs = process.argv.slice(2);
const plaintext = process.argv.slice(2);
// console.log('plaintext: ', plaintext);
// console.log ("sha512: " + sha512(myArgs[0]) );
// console.log (sha512(plaintext[0]));


let icpm_hash_token = sha512(plaintext[0])
console.log (icpm_hash_token)



