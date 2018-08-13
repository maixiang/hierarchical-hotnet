#!/usr/bin/env bash

data=$PWD/data
intermediate=$PWD/intermediate
results=$PWD/results

num_permutations=100

# Hierarchical HotNet is parallelizable, but this script runs each script
# sequentially.  Please see example_commands_parallel.sh for a parallelized
# example.

# Compile Fortran module.
cd ../src
f2py -c fortran_module.f95 -m fortran_module > /dev/null
cd ..

################################################################################
#
#   Prepare data.
#
################################################################################

# Create data, intermediate data and results, and results directories.
mkdir -p $data
mkdir -p $results

for network in network_1
do
    for score in score_1 score_2
    do
        mkdir -p "$intermediate"/"$network"_"$score"
        cp $data/index_gene_"$network".tsv $intermediate/"$network"_"$score"/index_gene_"$network"_0.tsv
        cp $data/edge_list_"$network".tsv $intermediate/"$network"_"$score"/edge_list_"$network"_0.tsv
        cp $data/scores_"$score".tsv $intermediate/"$network"_"$score"/scores_"$score"_0.tsv
    done
done

################################################################################
#
#   Construct similarity matrices.
#
################################################################################

# Choose beta parameter.
echo "Choosing beta parameters..."

for network in network_1
do
    python src/choose_beta.py \
        -i $data/edge_list_"$network".tsv \
        -o $intermediate/beta_"$network".txt
done

# Construct similarity matrix.
echo "Construct similarity matrices..."

for network in network_1
do
    beta=`cat $intermediate/beta_"$network".txt`

    python src/create_similarity_matrix.py \
        -i $data/edge_list_"$network".tsv \
        -b $beta \
        -o $intermediate/similarity_matrix_"$network".h5
done

################################################################################
#
#   Permute data.
#
################################################################################

# Permute networks.  We do not use permuted networks in this example, but we
# generate them here to test the network permutation scripts.
echo "Permuting networks..."

for network in network_1
do
    # Preserve connectivity of the observed graph.
    for i in `seq 1 4`
    do
        python src/permute_network.py \
            -i $intermediate/"$network"_"$score"/edge_list_"$network"_0.tsv \
            -s "$i" \
            -c \
            -o $intermediate/"$network"_"$score"/edge_list_"$network"_"$i".tsv
    done

    # Do not preserve connectivity of the observed graph.
    for i in `seq 1 4`
    do
        python src/permute_network.py \
            -i $intermediate/"$network"_"$score"/edge_list_"$network"_0.tsv \
            -s "$i" \
            -o $intermediate/"$network"_"$score"/edge_list_"$network"_"$i".tsv
    done
done

# Permute scores.  The permuted scores only exchange scores between vertices in
# the network.
echo "Permuting scores..."

for network in network_1
do
    for score in score_1 score_2
    do
        python src/find_permutation_bins.py \
            -gsf $intermediate/"$network"_"$score"/scores_"$score"_0.tsv \
            -igf $intermediate/"$network"_"$score"/index_gene_"$network"_0.tsv \
            -elf $intermediate/"$network"_"$score"/edge_list_"$network"_0.tsv \
            -ms  1000 \
            -o   $intermediate/"$network"_"$score"/score_bins.tsv

        for i in `seq 1 4`
        do
            python src/permute_scores.py \
                -i  $intermediate/"$network"_"$score"/scores_"$score"_0.tsv \
                -bf $intermediate/"$network"_"$score"/score_bins.tsv \
                -o  $intermediate/"$network"_"$score"/scores_"$score"_"$i".tsv
        done
    done
done

################################################################################
#
#   Construct hierarchies.
#
################################################################################

# Construct hierarchies.
echo "Constructing hierarchies..."

for network in network_1
do
    for score in score_1 score_2
    do
        for i in `seq 0 $num_permutations`
        do
            python src/construct_hierarchy.py \
                -smf  $intermediate/similarity_matrix_"$network".h5 \
                -igf  $intermediate/"$network"_"$score"/index_gene_"$network"_0.tsv \
                -gsf  $intermediate/"$network"_"$score"/scores_"$score"_"$i".tsv \
                -helf $intermediate/"$network"_"$score"/hierarchy_edge_list_"$i".tsv \
                -higf $intermediate/"$network"_"$score"/hierarchy_index_gene_"$i".tsv
        done
    done
done

# Cut hierarchies.
echo "Cutting hierarchies..."

for network in network_1
do
    for score in score_1 score_2
    do
        echo $(for i in `seq $num_permutations`; do echo " $intermediate/"$network"_"$score"/hierarchy_edge_list_"$i".tsv "; done) > $intermediate/"$network"_"$score"/hierarchy_edge_list_filenames.txt
        echo $(for i in `seq $num_permutations`; do echo " $intermediate/"$network"_"$score"/hierarchy_index_gene_"$i".tsv "; done) > $intermediate/"$network"_"$score"/hierarchy_index_gene_filenames.txt

        for i in `seq 0 $num_permutations`
        do
            python src/choose_cut_file.py \
                -oelf $intermediate/"$network"_"$score"/hierarchy_edge_list_"$i".tsv \
                -oigf $intermediate/"$network"_"$score"/hierarchy_index_gene_"$i".tsv \
                -pelf $intermediate/"$network"_"$score"/hierarchy_edge_list_filenames.txt \
                -pigf $intermediate/"$network"_"$score"/hierarchy_index_gene_filenames.txt \
                -hf   $intermediate/"$network"_"$score"/height_"$i".txt \
                -sf   $intermediate/"$network"_"$score"/statistic_"$i".txt \
                -rf   $intermediate/"$network"_"$score"/ratio_"$i".txt
        done
    done
done

################################################################################
#
#   Process results.
#
################################################################################

# Plot cluster sizes.
echo "Plotting cluster sizes..."

for network in network_1
do
    for score in score_1 score_2
    do
        python src/plot_hierarchy_statistic.py \
            -oelf $intermediate/"$network"_"$score"/hierarchy_edge_list_0.tsv \
            -oigf $intermediate/"$network"_"$score"/hierarchy_index_gene_0.tsv \
            -pelf $(for i in `seq $num_permutations`; do echo -n " $intermediate/"$network"_"$score"/hierarchy_edge_list_"$i".tsv "; done) \
            -pigf $(for i in `seq $num_permutations`; do echo -n " $intermediate/"$network"_"$score"/hierarchy_index_gene_"$i".tsv "; done) \
            -l    $network $score \
            -o    $results/cluster_sizes_"$network"_"$score".pdf
    done
done

# Find clusters.
echo "Finding clusters..."

for network in network_1
do
    for score in score_1 score_2
    do
        height=`cat $intermediate/"$network"_"$score"/height_0.txt`

        python src/cut_hierarchy.py \
            -elf $intermediate/"$network"_"$score"/hierarchy_edge_list_0.tsv \
            -igf $intermediate/"$network"_"$score"/hierarchy_index_gene_0.tsv \
            -cc  height \
            -ct  $height \
            -o   $results/clusters_"$network"_"$score".tsv
    done
done

# Find p-values.
echo "Finding p-values..."

for network in network_1
do
    for score in score_1 score_2
    do
        python src/compute_p_value.py \
            -osf $intermediate/"$network"_"$score"/ratio_0.txt \
            -psf $(for i in `seq $num_permutations`; do echo -n " $intermediate/"$network"_"$score"/ratio_"$i".txt "; done) \
            -o   $results/p_value_"$network"_"$score".txt
    done
done

# Perform consensus.
echo "Performing consensus..."

python src/perform_consensus.py \
    -cf  $results/clusters_network_1_score_1.tsv $results/clusters_network_1_score_2.tsv \
    -igf $data/index_gene_network_1.tsv $data/index_gene_network_1.tsv \
    -elf $data/edge_list_network_1.tsv $data/edge_list_network_1.tsv \
    -n   network_1 network_1 \
    -s   score_1 score_2 \
    -t   2 \
    -o   $results/consensus_nodes.tsv \
    -oo  $results/consensus_edges.tsv
