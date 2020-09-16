// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Fuzzilli

fileprivate let ForceV8TurbofanGenerator = CodeGenerator("ForceV8TurbofanGenerator", input: .function()) { b, f in
    guard let arguments = b.generateCallArguments(for: f) else { return }
    
    let start = b.loadInt(0)
    let end = b.loadInt(100)
    let step = b.loadInt(1)
    b.forLoop(start, .lessThan, end, .Add, step) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let AimForTypeConfusion = CodeGenerator("AimForTypeConfusion") { b in
    func funcbody(_ vars: [Variable])
    {
        b.generate(n: 5)
        
        let code = b.codeString() {
            b.generateRecursive()
            return b.randVar()
        }
        let eval = b.loadBuiltin("eval")
        b.callFunction(eval, withArgs: [code])

        let array = b.randVar(ofType: .object())! // maybe .jsArray?
        let index = b.genIndex()
        b.loadElement(index, of: array)
        b.doReturn(value: b.randVar())
    }
    let f = withEqualProbability({
        b.definePlainFunction(withSignature: FunctionSignature(withParameterCount: Int.random(in: 2...5), hasRestParam: probability(0.4)), funcbody)
    },{
        b.defineStrictFunction(withSignature: FunctionSignature(withParameterCount: Int.random(in: 2...5), hasRestParam: probability(0.4)), funcbody)
    })
    let initialArgs = b.generateCallArguments(for: f)!
    let optimisationArgs = b.generateCallArguments(for: f)!
    let triggeredArgs = b.generateCallArguments(for: f)!

    b.callFunction(f, withArgs: initialArgs)

    // Ensure optimisation - watch out with timeouts! 
    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(Int64.random(in: 100 ... 20000)), .Add, b.loadInt(1)) { _ in
        b.callFunction(f, withArgs: optimisationArgs)
     }

    b.callFunction(f, withArgs: triggeredArgs)
}

let v8Profile = Profile(
    processArguments: ["--debug-code",
                       "--expose-gc",
                       "--single-threaded",
                       "--predictable",
                       "--allow-natives-syntax",
                       "--interrupt-budget=1024",
                       "--assert-types",
                       "--fuzzing",
                       "--reprl"],
    
    processEnv: [:],
    
    codePrefix: """
                function main() {
                """,
    
    codeSuffix: """
                }
                %NeverOptimizeFunction(main);
                main();
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    crashTests: ["fuzzilli('FUZZILLI_CRASH', 0)", "fuzzilli('FUZZILLI_CRASH', 1)", "fuzzilli('FUZZILLI_CRASH', 2)"],
    
    additionalCodeGenerators: WeightedList<CodeGenerator>([
        (ForceV8TurbofanGenerator, 10),
        (AimForTypeConfusion, 20)
    ]),
       
    disabledCodeGenerators: [],
    
    additionalBuiltins: [
        "gc"                : .function([] => .undefined),
    ]
)

