using Flux
using Random
using Flux.Data: DataLoader
using Flux: onehotbatch, onecold, onehot, @epochs
using NNlib
using DelimitedFiles
include("DataPreparation.jl")
include("Evaluation.jl")
include("ModelDefinitions.jl")
include("Parameters.jl")


# call parameters
params = Hyperparameters()
data = DataParameters(file_name = "/data/HPAIV_train_set.csv", input_length = 249, aa_universe = "ABCDEFGHIKLMNPQRSTVWY?")


function training(MSA, AA_dict, params, data, device)
    @unpack lossFunction, η, optimizer, epochs = params
    @unpack file_name, input_length = data
    
    data_encoded = MSA_encode(MSA, AA_dict)
    decision = MSA[1:end, end]
    train = [(data_encoded[i,:], decision[i]) for i in 1:length(decision)]
    
    # construct model
    model = create_perceptron(params, data) |> device

    # optimizer
    opt = Flux.setup(optimizer(η), model)
    
    # Training in epochs
    for epoch in 1:epochs
        for (x, y) in train
            #x, y = device(x), device(y)
            gs = gradient(m -> lossFunction(m(x), y), model)
            Flux.Optimise.update!(opt, model, gs[1])
        end
    end

    return model
end



function train_network(params, data)
    device = cpu
    @unpack lossFunction, η, optimizer, epochs, cv, seed, mode = params
    @unpack file_name, input_length = data



    Random.seed!(seed)

    # get data
    AA_dict = AA_to_int(data)
    MSA = readdlm(file_name, ',')
    
    # undersampling might be necessary
    #MSA = undersample(MSA[1:end,:])

    #shuffle MSA (very important, otherwise very bad results)
    MSA = MSA[shuffle(1:end), :]

    # initialize performance measures
    avg_acc = 0
    avg_loss = 0
    perf = [0, 0, 0, 0]

    model = 0

    # TODO: make functions for epoch, optimizing part etc

    for cross in 1:cv
        train_data, test_data = get_data(MSA, AA_dict, cross, cv)

        # construct model
        model = create_perceptron(params, data) |> device

        # optimizer
        opt = Flux.setup(optimizer(η), model)
        
        # Training
        test_loss, test_acc = 0, 0
        for epoch in 1:epochs
            for (x, y) in train_data
                #x, y = device(x), device(y)
                gs = gradient(m -> lossFunction(m(x), y), model)
                Flux.Optimise.update!(opt, model, gs[1])
            end
        end

        # evaluate performance for current fold
        test_loss, test_acc, perf_measure = loss_and_accuracy(test_data, model, device, params)
        println(" test_loss = $test_loss, test_accuracy = $test_acc, Performance: $perf_measure")
        
        # update average performance
        avg_acc += test_acc/cv
        avg_loss += test_loss/cv
        perf += perf_measure
    end

    println("Avg. accuracy: ", avg_acc, "\t avg. loss: $avg_loss", "\t Performance: $perf")
    
    # model trained on complete data
    model = training(MSA, AA_dict, params, data, device)

    # return last model
    return model, avg_acc, avg_loss, AA_dict
end

